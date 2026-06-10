// Package rutracker parses a rutracker.org topic page into a Track
// payload ready for the admin import endpoint.
//
// Rutracker is a torrent forum: pages are HTML, magnets are embedded,
// metadata lives in the title and the post body. The parser is
// intentionally conservative — when in doubt it leaves fields blank
// and lets the operator fill them in via the admin panel.
//
// IMPORTANT: this importer is a CONVENIENCE for operators who self-host
// Librefy and want to seed their catalog faster. The official build's
// admin endpoint that drives it requires LIBREFY_ADMIN_TOKEN, so
// untrusted users can't trigger fetches. The operator is responsible
// for ensuring the magnets they import point at content they're
// legally allowed to redistribute.
package rutracker

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"golang.org/x/net/html"
	"golang.org/x/text/encoding/charmap"
)

// Result mirrors the shape of the admin Track upsert endpoint.
//
// When the topic represents a compilation / album, [Tracks] holds the
// parsed tracklist; [Title]/[Artist]/[Album] describe the release as
// a whole. For single-track releases, [Tracks] is empty and the
// top-level fields describe the one and only track.
type Result struct {
	Title       string            `json:"title"`
	Artist      string            `json:"artist"`
	Album       string            `json:"album,omitempty"`
	Year        string            `json:"year,omitempty"`
	Magnet      string            `json:"magnet"`
	InfoHash    string            `json:"infoHash"`
	ArtworkURL  string            `json:"artworkUrl,omitempty"`
	Tags        []string          `json:"tags,omitempty"`
	Source      string            `json:"source"`
	RawMetadata map[string]string `json:"rawMetadata,omitempty"`

	// Tracks is the parsed tracklist when the release is a compilation
	// or multi-track album. Each entry maps to one Track row in the DB,
	// sharing the same magnet and info-hash but with its own FileIndex.
	Tracks []TrackEntry `json:"tracks,omitempty"`
}

// TrackEntry is a single song parsed from the topic body's tracklist.
type TrackEntry struct {
	// FileIndex is the zero-based position of this track in the torrent's
	// file list (when files are ordered by name). The libtorrent bridge
	// uses it to serve the right audio file from the swarm.
	FileIndex  int    `json:"fileIndex"`
	Position   int    `json:"position"` // 1-based ordinal as printed on the page
	Title      string `json:"title"`
	Artist     string `json:"artist"`
	DurationMS int64  `json:"durationMs,omitempty"`
}

// Parser fetches and parses a single rutracker topic URL.
type Parser struct {
	HTTP *http.Client
}

func NewParser() *Parser {
	return &Parser{HTTP: &http.Client{Timeout: 15 * time.Second}}
}

var topicURLPattern = regexp.MustCompile(`rutracker\.org/forum/viewtopic\.php\?t=\d+`)

// Parse fetches the topic at the given URL and extracts a Result.
func (p *Parser) Parse(ctx context.Context, rawURL string) (*Result, error) {
	if !topicURLPattern.MatchString(rawURL) {
		return nil, fmt.Errorf("not a rutracker topic url: %s", rawURL)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	// Rutracker pages still ship as windows-1251 by default; pretend to
	// be a normal browser so anti-bot heuristics don't intercept.
	req.Header.Set("User-Agent",
		"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "+
			"(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
	req.Header.Set("Accept-Language", "ru,en;q=0.7")

	resp, err := p.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	// Rutracker is windows-1251 — decode upfront so the goquery /
	// html parser sees correct runes.
	utf8body, err := charmap.Windows1251.NewDecoder().Bytes(body)
	if err != nil {
		// Best-effort: assume already UTF-8 if conversion fails.
		utf8body = body
	}

	doc, err := html.Parse(strings.NewReader(string(utf8body)))
	if err != nil {
		return nil, fmt.Errorf("parse html: %w", err)
	}

	res := &Result{
		Source:      rawURL,
		RawMetadata: map[string]string{},
	}

	// --- title ---
	title := strings.TrimSpace(textOf(findByID(doc, "topic-title")))
	if title == "" {
		// fall back to <title> tag content
		title = textOf(findFirstTag(doc, "title"))
		title = strings.TrimSpace(strings.TrimSuffix(title, " :: rutracker.org"))
	}
	res.Title, res.Artist, res.Album, res.Year = splitReleaseTitle(title)

	// --- magnet ---
	if m := findMagnet(doc); m != "" {
		res.Magnet = m
		res.InfoHash = strings.ToUpper(extractInfoHash(m))
	}

	// --- artwork: prefer post-body images larger than icons ---
	if art := findArtwork(doc); art != "" {
		res.ArtworkURL = art
	}

	// --- key/value pairs from the topic body ("Жанр: …", "Год выпуска: …") ---
	body2 := findByClass(doc, "post_body")
	if body2 != nil {
		kvPairs := extractKVPairs(body2)
		for k, v := range kvPairs {
			res.RawMetadata[k] = v
		}
		// Promote a few well-known keys.
		if g := pickFirst(kvPairs, "Жанр", "Genre", "Стиль"); g != "" {
			for _, t := range splitTags(g) {
				res.Tags = append(res.Tags, t)
			}
		}
		if res.Year == "" {
			if y := pickFirst(kvPairs, "Год выпуска", "Год", "Year"); y != "" {
				res.Year = trimYear(y)
			}
		}
		if res.Artist == "" {
			if a := pickFirst(kvPairs, "Исполнитель", "Artist"); a != "" {
				res.Artist = a
			}
		}
		if res.Album == "" {
			if a := pickFirst(kvPairs, "Альбом", "Album", "Название"); a != "" {
				res.Album = a
			}
		}
	}

	// --- classify: audiobook vs. music ---
	// The classifier looks at the subforum the topic lives in (most
	// reliable), the topic title, and the post body. We need to do
	// this BEFORE parsing the tracklist because the rules for "what
	// counts as a track row" differ between music and spoken content.
	var bodyText string
	if body2 != nil {
		bodyText = textOf(body2)
	}
	kind := classifyKind(title, bodyText, doc)

	switch kind {
	case KindAudiobook:
		// Audiobook: parse chapters with the permissive chapter
		// grammar (no Artist - Title requirement) and surface a
		// matching tag so the client renders an audiobook badge.
		if bodyText != "" {
			res.Tracks = extractChapters(bodyText)
		}
		res.Tags = append(res.Tags, "audiobook")
		// Promote narrator / author into top-level fields when the
		// post carries them under a recognised label. We've already
		// captured them in RawMetadata via extractKVPairs.
		if narrator := pickFirst(res.RawMetadata,
			"Чтец", "Читает", "Начитал", "Озвучивает", "Narrator"); narrator != "" {
			res.RawMetadata["Narrator"] = narrator
			// If we don't have an Artist yet, use the narrator —
			// that matches how audiobook stores normally display
			// the credit on the cover.
			if res.Artist == "" {
				res.Artist = narrator
			}
		}
		if author := pickFirst(res.RawMetadata,
			"Автор", "Author"); author != "" {
			res.RawMetadata["Author"] = author
			if res.Album == "" {
				res.Album = author
			}
		}
	default:
		// Music: existing strict tracklist parser.
		if body2 != nil {
			res.Tracks = extractTracklist(bodyText)
		}
	}

	if res.Magnet == "" {
		return nil, errors.New("no magnet link found on page")
	}
	if res.Title == "" {
		res.Title = "Untitled"
	}
	return res, nil
}

// trackLinePattern matches lines like:
//
//	"01. Artist - Title (Original Mix) [7:12]"
//	"1.  Artist feat. X - Title [03:45]"
//	"01 - Artist - Title"            (no brackets)
//	"01) Artist – Title [6:31]"      (en-dash)
//
// Position is required so we don't pick up random hyphenated lines from
// the post body. Duration in brackets is optional.
var trackLinePattern = regexp.MustCompile(
	`^\s*(\d{1,3})\s*[.):\-]\s+(.+?)\s+[-–—]\s+(.+?)\s*(?:\[\s*(\d{1,3}):(\d{2})(?::(\d{2}))?\s*\])?\s*$`,
)

// htmlEntities the tracklist parser needs to undo because the input
// originates from textOf(node) which preserves them.
var htmlEntityReplacer = strings.NewReplacer(
	"&amp;", "&",
	"&#39;", "'",
	"&quot;", `"`,
	"&lt;", "<",
	"&gt;", ">",
	"&nbsp;", " ",
)

// trackInlinePattern is the same shape as trackLinePattern but anchors
// on word boundaries so we can extract entries from a single blob of
// text where rutracker shipped the whole tracklist on one HTML line.
var trackInlinePattern = regexp.MustCompile(
	`(?:^|[\s\)\]])\s*(\d{1,3})\s*[.):\-]\s+([^\n\[]+?)\s+[-–—]\s+([^\n\[]+?)\s*\[\s*(\d{1,3}):(\d{2})(?::(\d{2}))?\s*\]`,
)

// extractTracklist scans the post body for a numbered tracklist and
// returns the parsed entries. We assume the file order in the torrent
// follows the tracklist order (this is overwhelmingly the convention
// on rutracker audio uploads); FileIndex is therefore set to Position-1
// as a sane default. The client may override it after listing the
// torrent's actual file table.
//
// Rutracker emits tracklists in two flavours: properly broken into
// lines, or jammed onto one line with [duration] markers as the only
// separator. We try the line-based parse first, then fall back to a
// duration-anchored regex sweep.
func extractTracklist(body string) []TrackEntry {
	body = htmlEntityReplacer.Replace(body)

	if entries := parseLineByLine(body); len(entries) >= 2 {
		return entries
	}
	return parseInline(body)
}

func parseLineByLine(body string) []TrackEntry {
	var out []TrackEntry
	var lastPos int
	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || len(line) > 300 {
			continue
		}
		m := trackLinePattern.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		entry, ok := buildEntry(m, lastPos)
		if !ok {
			continue
		}
		out = append(out, entry)
		lastPos = entry.Position
	}
	if len(out) < 2 || out[0].Position != 1 {
		return nil
	}
	return out
}

// parseInline handles posts where the entire tracklist is on one line
// because rutracker rendered them without <br>. We rely on the [m:ss]
// duration marker that every entry carries to find the boundary
// between "Artist - Title [3:21]" and the start of the next "NN.".
func parseInline(body string) []TrackEntry {
	matches := trackInlinePattern.FindAllStringSubmatch(body, -1)
	var out []TrackEntry
	var lastPos int
	for _, m := range matches {
		entry, ok := buildEntry(m, lastPos)
		if !ok {
			continue
		}
		out = append(out, entry)
		lastPos = entry.Position
	}
	if len(out) < 2 || out[0].Position != 1 {
		return nil
	}
	return out
}

// buildEntry materialises a regex match (in either line-by-line or
// inline form — they capture the same five-or-six submatch shape) into
// a validated TrackEntry. Returns ok=false to signal "skip this match".
func buildEntry(m []string, lastPos int) (TrackEntry, bool) {
	pos, _ := strconv.Atoi(m[1])
	if pos <= 0 || pos > 500 {
		return TrackEntry{}, false
	}
	// Allow a small jump (re-issues, hidden tracks) but reject huge gaps
	// — those usually mean we matched something unrelated.
	if pos > lastPos+5 && lastPos > 0 {
		return TrackEntry{}, false
	}
	artist := strings.TrimSpace(m[2])
	title := strings.TrimSpace(m[3])
	// Inline matches sometimes pick up trailing punctuation from the
	// previous track's duration brace. Trim leading/trailing junk.
	artist = strings.Trim(artist, " .,:;-–—")
	title = strings.Trim(title, " .,:;-–—")
	if artist == "" || title == "" || len(artist) > 120 || len(title) > 200 {
		return TrackEntry{}, false
	}
	var durMs int64
	if len(m) >= 6 && m[4] != "" && m[5] != "" {
		h, mm, ss := 0, 0, 0
		if len(m) >= 7 && m[6] != "" {
			h, _ = strconv.Atoi(m[4])
			mm, _ = strconv.Atoi(m[5])
			ss, _ = strconv.Atoi(m[6])
		} else {
			mm, _ = strconv.Atoi(m[4])
			ss, _ = strconv.Atoi(m[5])
		}
		durMs = int64((h*3600 + mm*60 + ss) * 1000)
	}
	return TrackEntry{
		Position:   pos,
		FileIndex:  pos - 1,
		Title:      title,
		Artist:     artist,
		DurationMS: durMs,
	}, true
}

// ------------------ HTML helpers ------------------

func findByID(n *html.Node, id string) *html.Node {
	var found *html.Node
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if found != nil || node == nil {
			return
		}
		if node.Type == html.ElementNode {
			for _, a := range node.Attr {
				if a.Key == "id" && a.Val == id {
					found = node
					return
				}
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return found
}

func findByClass(n *html.Node, class string) *html.Node {
	var found *html.Node
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if found != nil || node == nil {
			return
		}
		if node.Type == html.ElementNode {
			for _, a := range node.Attr {
				if a.Key == "class" && strings.Contains(a.Val, class) {
					found = node
					return
				}
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return found
}

func findFirstTag(n *html.Node, tag string) *html.Node {
	var found *html.Node
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if found != nil || node == nil {
			return
		}
		if node.Type == html.ElementNode && node.Data == tag {
			found = node
			return
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return found
}

// textOf flattens an HTML subtree to text, preserving line structure:
// <br>, <p>, <li>, <div> all imply a newline so the downstream
// tracklist parser sees the same lines a browser would render.
func textOf(n *html.Node) string {
	if n == nil {
		return ""
	}
	var sb strings.Builder
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if node == nil {
			return
		}
		if node.Type == html.TextNode {
			sb.WriteString(node.Data)
		}
		if node.Type == html.ElementNode {
			switch node.Data {
			case "br", "p", "li", "div", "tr":
				sb.WriteByte('\n')
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
		if node.Type == html.ElementNode {
			switch node.Data {
			case "p", "li", "div", "tr":
				sb.WriteByte('\n')
			}
		}
	}
	walk(n)
	return sb.String()
}

// findMagnet locates the first <a href="magnet:..."> on the page.
func findMagnet(n *html.Node) string {
	var found string
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if found != "" || node == nil {
			return
		}
		if node.Type == html.ElementNode && node.Data == "a" {
			for _, a := range node.Attr {
				if a.Key == "href" && strings.HasPrefix(a.Val, "magnet:") {
					found = a.Val
					return
				}
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return found
}

// findArtwork returns the first reasonably-sized <var class="postImg"
// title="<url>"> or <img src=...> in the post body. Rutracker stores
// uploaded thumbnails in <var> and the actual URL in title; we prefer
// those when available.
func findArtwork(n *html.Node) string {
	body := findByClass(n, "post_body")
	if body == nil {
		body = n
	}
	var best string
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if best != "" || node == nil {
			return
		}
		if node.Type == html.ElementNode {
			switch node.Data {
			case "var":
				var class, title string
				for _, a := range node.Attr {
					if a.Key == "class" {
						class = a.Val
					}
					if a.Key == "title" {
						title = a.Val
					}
				}
				if strings.Contains(class, "postImg") && isImageURL(title) {
					best = title
					return
				}
			case "img":
				for _, a := range node.Attr {
					if a.Key == "src" && isImageURL(a.Val) && !isAvatar(a.Val) {
						best = a.Val
						return
					}
				}
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(body)
	return best
}

func isImageURL(u string) bool {
	low := strings.ToLower(u)
	return strings.HasSuffix(low, ".jpg") ||
		strings.HasSuffix(low, ".jpeg") ||
		strings.HasSuffix(low, ".png") ||
		strings.HasSuffix(low, ".webp") ||
		strings.Contains(low, "/preview/")
}

func isAvatar(u string) bool {
	low := strings.ToLower(u)
	return strings.Contains(low, "/avatar") ||
		strings.Contains(low, "/icon") ||
		strings.Contains(low, "smiles/")
}

// extractKVPairs reads sequential text lines like "Жанр: Rock"
// from the topic body.
func extractKVPairs(body *html.Node) map[string]string {
	text := textOf(body)
	out := map[string]string{}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Most rutracker posts use "Key: Value" or "Key — Value".
		idx := strings.Index(line, ":")
		if idx < 1 || idx > 40 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if key == "" || val == "" {
			continue
		}
		// First occurrence wins (avoid being overwritten by nested key/value
		// dumps further down the post).
		if _, exists := out[key]; !exists {
			out[key] = val
		}
	}
	return out
}

func pickFirst(m map[string]string, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k]; ok && v != "" {
			return v
		}
	}
	return ""
}

func splitTags(s string) []string {
	var out []string
	for _, t := range regexp.MustCompile(`[,;/]| - `).Split(s, -1) {
		t = strings.TrimSpace(t)
		if t != "" && len(t) < 40 {
			out = append(out, t)
		}
	}
	return out
}

func trimYear(s string) string {
	m := regexp.MustCompile(`(19|20)\d{2}`).FindString(s)
	return m
}

// extractInfoHash pulls the btih hash out of a magnet URI.
func extractInfoHash(magnet string) string {
	u, err := url.Parse(magnet)
	if err != nil {
		return ""
	}
	for _, xt := range u.Query()["xt"] {
		if strings.HasPrefix(xt, "urn:btih:") {
			return strings.TrimPrefix(xt, "urn:btih:")
		}
	}
	return ""
}

// splitReleaseTitle turns rutracker's verbose topic title into pieces.
// Common patterns:
//
//	"(Genre) Artist - Album - Year, MP3, 320 kbps"
//	"Artist - Album [Year, FLAC]"
//	"Artist - Title (Single) [2020, MP3]"
//
// Best-effort — leaves fields empty when the structure isn't clear.
func splitReleaseTitle(raw string) (title, artist, album, year string) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return
	}
	// Strip leading "(Genre) " if present.
	if m := regexp.MustCompile(`^\(([^)]+)\)\s*`).FindString(s); m != "" {
		s = strings.TrimPrefix(s, m)
	}
	// Year — last 4-digit year in the string.
	if y := regexp.MustCompile(`(19|20)\d{2}`).FindAllString(s, -1); len(y) > 0 {
		year = y[len(y)-1]
	}
	// Cut everything from the first comma after the album — usually format info.
	// Try "Artist - Album" before the first comma.
	mainPart := s
	if i := strings.IndexAny(s, ",["); i > 0 {
		mainPart = strings.TrimSpace(s[:i])
	}
	if i := strings.Index(mainPart, " - "); i > 0 {
		artist = strings.TrimSpace(mainPart[:i])
		album = strings.TrimSpace(mainPart[i+3:])
		title = album
	} else {
		title = mainPart
	}
	return
}
