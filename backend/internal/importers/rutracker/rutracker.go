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
	"strings"
	"time"

	"golang.org/x/net/html"
	"golang.org/x/text/encoding/charmap"
)

// Result mirrors the shape of the admin Track upsert endpoint.
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

	if res.Magnet == "" {
		return nil, errors.New("no magnet link found on page")
	}
	if res.Title == "" {
		res.Title = "Untitled"
	}
	return res, nil
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
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
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
