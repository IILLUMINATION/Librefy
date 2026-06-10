// audiobook.go — heuristics that tell us whether a rutracker topic is
// an audiobook / radio play rather than a music release.
//
// Why this matters for Librefy:
//   - The generic tracklist parser (rutracker.go) expects rows that
//     look like "01. Artist - Title [3:21]". Audiobook posts almost
//     never look like that: chapters are named "Часть 01" / "Глава II"
//     without a separate artist field, and durations span hours.
//   - When the parser fails to recognise any structure it returns
//     zero tracks, and the operator ends up with an empty album. When
//     it DOES match (because the poster manually numbered chapters),
//     the entries are spuriously labelled "Author — Chapter N" which
//     is technically true but plays back nothing like a music
//     library wants.
//   - We want audiobooks to be a first-class but minimal citizen:
//     classify them, keep them in the catalog tagged "audiobook", and
//     let the Dart player treat them as ordinary playlists.
//
// The classifier is conservative: when in doubt we say "music" so the
// existing tracklist path runs. Audiobook section IDs on rutracker
// (the most reliable signal) are listed below and stable for years.
package rutracker

import (
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/net/html"
)

// TrackKind is the bucket a rutracker topic falls into.
type TrackKind int

const (
	// KindMusic — default; the topic looks like a regular music release.
	KindMusic TrackKind = iota
	// KindAudiobook — the topic is an audiobook, radio play, or
	// non-music spoken content. Should be imported as a playlist of
	// chapter-tracks (same magnet, distinct fileIndex per chapter).
	KindAudiobook
)

// audiobookSectionAnchorKeywords are substrings that, when found in
// the *text* of a breadcrumb anchor (the visible label of a subforum
// link), mark the surrounding topic as audiobook content. We classify
// on the anchor text rather than the numeric `f=N` because rutracker
// reorganises subforums occasionally; the textual labels are far more
// stable than the integer IDs underneath them. The parent category
// "Аудиокниги" sits above every audiobook subforum and is the single
// strongest signal we get from the page chrome.
var audiobookSectionAnchorKeywords = []string{
	"аудиокниг",      // "Аудиокниги" parent, plus inflections
	"аудиоспектакл",  // "Аудиоспектакли"
	"радиоспектакл",  // "Радиоспектакли, история, мемуары" etc.
	"литературные чтения",
}

// audiobookTitleKeywords are substrings (case-folded) that, when found
// in the topic title, strongly suggest the post is an audiobook even
// when we don't know the section ID. Hits are OR'd — any one is
// enough — because rutracker conventions are remarkably consistent
// here ("Аудиокнига" is almost never used as a music album title).
var audiobookTitleKeywords = []string{
	"аудиокниг", // covers "Аудиокнига" and any inflection
	"аудиоспектакл",
	"радиоспектакл",
	"audiobook",
	"radio play",
}

// audiobookPostMarkers are key labels that crop up in audiobook posts
// when the poster fills out a structured metadata block. None of them
// individually justifies a reclassification — music posts sometimes
// mention "Автор" — but two or more in the same body strongly suggest
// spoken content.
var audiobookPostMarkers = []string{
	"чтец:",
	"читает:",
	"начитал:",
	"озвучивает:",
	"narrated by",
	"автор:",
	"время звучания:",
	"продолжительность:",
}

// classifyKind returns whether the given topic looks like an audiobook
// or a regular music release.
//
//   - title:   raw <title> / topic-title text
//   - postText: flattened text of the post body (output of textOf)
//   - doc:     parsed HTML root, used to walk the breadcrumb for the
//     subforum link. May be nil — we degrade gracefully.
func classifyKind(title, postText string, doc *html.Node) TrackKind {
	// 1. Breadcrumb-based: scan the anchor labels of every link to a
	//    viewforum.php page and look for "Аудиокниги" / similar. This
	//    catches every audiobook subforum without us having to hard-
	//    code the integer ID for each.
	if hit := matchBreadcrumbAudiobook(doc); hit {
		return KindAudiobook
	}

	lcTitle := strings.ToLower(title)
	for _, kw := range audiobookTitleKeywords {
		if strings.Contains(lcTitle, kw) {
			return KindAudiobook
		}
	}

	// 3. Body markers: count how many spoken-content metadata labels
	//    the post carries. Two or more flips the verdict.
	lcBody := strings.ToLower(postText)
	hits := 0
	for _, m := range audiobookPostMarkers {
		if strings.Contains(lcBody, m) {
			hits++
			if hits >= 2 {
				return KindAudiobook
			}
		}
	}

	return KindMusic
}

// matchBreadcrumbAudiobook walks every <a href="viewforum.php?f=N">
// link on the page and checks its visible text for the audiobook
// anchor keywords. Returns true on first hit. Robust to forum
// renumbering because we never compare integer IDs.
func matchBreadcrumbAudiobook(n *html.Node) bool {
	if n == nil {
		return false
	}
	var hit bool
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if hit || node == nil {
			return
		}
		if node.Type == html.ElementNode && node.Data == "a" {
			var isForumLink bool
			for _, a := range node.Attr {
				if a.Key == "href" && strings.Contains(a.Val, "viewforum.php") {
					isForumLink = true
					break
				}
			}
			if isForumLink {
				lc := strings.ToLower(anchorText(node))
				for _, kw := range audiobookSectionAnchorKeywords {
					if strings.Contains(lc, kw) {
						hit = true
						return
					}
				}
			}
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return hit
}

// anchorText flattens an <a> element's visible text. Lighter than
// textOf because anchors never contain block-level descendants in
// practice — we just need the concatenated text nodes.
func anchorText(a *html.Node) string {
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
	walk(a)
	return sb.String()
}

// ---- chapter parsing -------------------------------------------------

// chapterLinePattern matches lines that look like an audiobook chapter:
//
//	"01. Глава первая"
//	"01 - Глава 1. Начало"
//	"Часть 1"
//	"Глава 12 - Развязка"
//	"01. Иванов И.И. - Преступление и наказание (часть 1)"  ← still ok
//
// We require either a leading number with a separator OR an explicit
// "Глава"/"Часть"/"Chapter"/"Part" keyword followed by a number. Plain
// "Title — Subtitle" lines are NOT enough; that would catch random
// post copy.
var chapterLinePattern = regexp.MustCompile(
	`^\s*(?:` +
		// case 1: "01.", "01 -", "01)" etc.
		`(\d{1,3})\s*[.):\-]\s+(.+?)` +
		`|` +
		// case 2: "Глава 1[: -] …", "Часть 12 …", "Chapter 7 …"
		`(?:[Гг]лава|[Чч]асть|[Cc]hapter|[Pp]art)\s+(\d{1,3})(?:\s*[.:\-]\s*(.+?))?` +
		`)` +
		`\s*(?:\[\s*(\d{1,3}):(\d{2})(?::(\d{2}))?\s*\])?\s*$`,
)

// extractChapters scans the post body for a numbered chapter list and
// returns the parsed entries. Mirrors extractTracklist in spirit but
// is far more permissive about the per-line shape (chapter posts on
// rutracker are written by humans with little structural discipline).
//
// The returned entries get FileIndex = Position-1, same default as
// music tracklists. If file order in the torrent doesn't match, the
// admin operator can fix it after import.
func extractChapters(body string) []TrackEntry {
	body = htmlEntityReplacer.Replace(body)
	var out []TrackEntry
	var lastPos int
	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || len(line) > 300 {
			continue
		}
		entry, ok := chapterEntryFromLine(line, lastPos)
		if !ok {
			continue
		}
		out = append(out, entry)
		lastPos = entry.Position
	}
	if len(out) < 2 {
		return nil
	}
	// Require the first chapter we picked up to be 1 — if it's 5, we
	// almost certainly mis-anchored on a stray "5. Note about format"
	// line and the real chapter list is elsewhere.
	if out[0].Position != 1 {
		return nil
	}
	return out
}

// chapterEntryFromLine parses one trimmed line into a chapter entry.
// Two patterns are accepted (see chapterLinePattern); we route the
// match through whichever capture group set fired.
func chapterEntryFromLine(line string, lastPos int) (TrackEntry, bool) {
	m := chapterLinePattern.FindStringSubmatch(line)
	if m == nil {
		return TrackEntry{}, false
	}
	var (
		posStr, title string
	)
	switch {
	case m[1] != "":
		posStr, title = m[1], m[2]
	case m[3] != "":
		posStr, title = m[3], m[4]
	default:
		return TrackEntry{}, false
	}
	pos, err := strconv.Atoi(posStr)
	if err != nil || pos <= 0 || pos > 999 {
		return TrackEntry{}, false
	}
	// Reject implausible jumps so we don't merge two separate numbered
	// lists in the same post (e.g. a tracklist followed by a footnote
	// "5. Источник: …").
	if pos > lastPos+3 && lastPos > 0 {
		return TrackEntry{}, false
	}
	title = strings.TrimSpace(title)
	if title == "" {
		// "Часть 12" without a subtitle is still a valid chapter — fill
		// in a synthetic title so the UI has something to render.
		title = "Часть " + posStr
	}
	if len(title) > 200 {
		return TrackEntry{}, false
	}
	var durMs int64
	if len(m) >= 8 && m[5] != "" && m[6] != "" {
		h, mm, ss := 0, 0, 0
		if m[7] != "" {
			h, _ = strconv.Atoi(m[5])
			mm, _ = strconv.Atoi(m[6])
			ss, _ = strconv.Atoi(m[7])
		} else {
			mm, _ = strconv.Atoi(m[5])
			ss, _ = strconv.Atoi(m[6])
		}
		durMs = int64((h*3600 + mm*60 + ss) * 1000)
	}
	return TrackEntry{
		Position:   pos,
		FileIndex:  pos - 1,
		Title:      title,
		// Artist field is repurposed for the narrator at the call site
		// (we don't know it from here, so leave empty).
		Artist:     "",
		DurationMS: durMs,
	}, true
}


