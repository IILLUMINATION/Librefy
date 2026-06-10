// Package ia implements a MusicProvider backed by the Internet Archive
// (archive.org) public search/metadata APIs.
//
// archive.org hosts an enormous catalogue of legally-redistributable
// audio (Live Music Archive, Netlabels, public-domain works, etc.).
// We only surface items that explicitly carry a permissive license tag
// (creativecommons / publicdomain). Items without a clear license are
// silently dropped — better to under-return than to mislead users.
package ia

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/librefy/librefy/backend/internal/domain"
	"github.com/librefy/librefy/backend/internal/service"
)

const (
	searchEndpoint   = "https://archive.org/advancedsearch.php"
	metadataEndpoint = "https://archive.org/metadata/"
	downloadEndpoint = "https://archive.org/download/"
)

// Provider implements service.MusicProvider against archive.org.
type Provider struct {
	http *http.Client
}

// New constructs a Provider. The supplied client should have a sensible
// timeout configured by the caller.
func New(c *http.Client) *Provider {
	if c == nil {
		c = &http.Client{Timeout: 10 * time.Second}
	}
	return &Provider{http: c}
}

// Name implements service.MusicProvider.
func (p *Provider) Name() string { return "ia" }

// Search queries the IA advancedsearch endpoint for audio items with
// permissive licenses.
func (p *Provider) Search(ctx context.Context, query string, limit int) (domain.SearchResult, error) {
	q := strings.TrimSpace(query)
	if q == "" {
		return domain.SearchResult{}, nil
	}
	// Restrict to audio mediatype, libre licenses only.
	expr := fmt.Sprintf(
		`(%s) AND mediatype:(audio) AND (licenseurl:(*creativecommons.org* OR *publicdomain*) OR possible-copyright-status:"NOT_IN_COPYRIGHT")`,
		q,
	)
	u, _ := url.Parse(searchEndpoint)
	v := u.Query()
	v.Set("q", expr)
	v.Set("fl[]", "identifier,title,creator,date,licenseurl")
	v.Set("rows", fmt.Sprintf("%d", limit))
	v.Set("page", "1")
	v.Set("output", "json")
	u.RawQuery = v.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return domain.SearchResult{}, err
	}
	resp, err := p.http.Do(req)
	if err != nil {
		return domain.SearchResult{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return domain.SearchResult{}, fmt.Errorf("ia search status %d", resp.StatusCode)
	}

	var body struct {
		Response struct {
			Docs []struct {
				Identifier string `json:"identifier"`
				Title      string `json:"title"`
				Creator    any    `json:"creator"`
				LicenseURL string `json:"licenseurl"`
			} `json:"docs"`
		} `json:"response"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return domain.SearchResult{}, err
	}

	out := domain.SearchResult{}
	for _, d := range body.Response.Docs {
		out.Tracks = append(out.Tracks, domain.Track{
			ID:         d.Identifier,
			Title:      d.Title,
			Artist:     creatorString(d.Creator),
			License:    licenseFromURL(d.LicenseURL),
			ArtworkURL: fmt.Sprintf("https://archive.org/services/img/%s", url.PathEscape(d.Identifier)),
			Provider:   "ia",
		})
	}
	return out, nil
}

// GetTrack hydrates a single IA item by hitting the metadata endpoint
// and picking the first playable audio file.
func (p *Provider) GetTrack(ctx context.Context, id string) (domain.Track, error) {
	meta, err := p.fetchMetadata(ctx, id)
	if err != nil {
		return domain.Track{}, err
	}
	file, ok := pickAudioFile(meta.Files)
	if !ok {
		return domain.Track{}, service.ErrNotFound
	}
	return domain.Track{
		ID:         id,
		Title:      firstNonEmpty(file.Title, meta.Metadata.Title, id),
		Artist:     firstNonEmpty(file.Creator, creatorString(meta.Metadata.Creator)),
		Album:      meta.Metadata.Album,
		ArtworkURL: fmt.Sprintf("https://archive.org/services/img/%s", url.PathEscape(id)),
		StreamURL:  downloadEndpoint + url.PathEscape(id) + "/" + url.PathEscape(file.Name),
		License:    licenseFromURL(meta.Metadata.LicenseURL),
		Provider:   "ia",
	}, nil
}

// ResolveStream picks the first audio file and returns its HTTP URL.
// IA does not expose magnet links directly, so P2P is unavailable here.
func (p *Provider) ResolveStream(ctx context.Context, id string) (service.StreamInfo, error) {
	meta, err := p.fetchMetadata(ctx, id)
	if err != nil {
		return service.StreamInfo{}, err
	}
	file, ok := pickAudioFile(meta.Files)
	if !ok {
		return service.StreamInfo{}, service.ErrNotFound
	}
	return service.StreamInfo{
		HTTPURL:  downloadEndpoint + url.PathEscape(id) + "/" + url.PathEscape(file.Name),
		MimeType: mimeForFormat(file.Format),
	}, nil
}

type iaMetadata struct {
	Metadata struct {
		Title      string `json:"title"`
		Creator    any    `json:"creator"`
		Album      string `json:"album"`
		LicenseURL string `json:"licenseurl"`
	} `json:"metadata"`
	Files []iaFile `json:"files"`
}

type iaFile struct {
	Name    string `json:"name"`
	Title   string `json:"title"`
	Creator string `json:"creator"`
	Format  string `json:"format"`
	Source  string `json:"source"`
}

func (p *Provider) fetchMetadata(ctx context.Context, id string) (*iaMetadata, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, metadataEndpoint+url.PathEscape(id), nil)
	if err != nil {
		return nil, err
	}
	resp, err := p.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ia metadata status %d", resp.StatusCode)
	}
	var m iaMetadata
	if err := json.NewDecoder(resp.Body).Decode(&m); err != nil {
		return nil, err
	}
	return &m, nil
}

func pickAudioFile(files []iaFile) (iaFile, bool) {
	// Prefer original > derivative; mp3 > anything else for broad client support.
	var best iaFile
	bestScore := -1
	for _, f := range files {
		score := -1
		switch {
		case strings.EqualFold(f.Format, "VBR MP3"), strings.EqualFold(f.Format, "MP3"):
			score = 50
		case strings.Contains(strings.ToLower(f.Format), "mp3"):
			score = 40
		case strings.Contains(strings.ToLower(f.Format), "ogg"):
			score = 30
		case strings.Contains(strings.ToLower(f.Format), "flac"):
			score = 20
		}
		if score < 0 {
			continue
		}
		if strings.EqualFold(f.Source, "original") {
			score += 5
		}
		if score > bestScore {
			best = f
			bestScore = score
		}
	}
	return best, bestScore >= 0
}

func mimeForFormat(format string) string {
	f := strings.ToLower(format)
	switch {
	case strings.Contains(f, "mp3"):
		return "audio/mpeg"
	case strings.Contains(f, "ogg"):
		return "audio/ogg"
	case strings.Contains(f, "flac"):
		return "audio/flac"
	default:
		return "audio/mpeg"
	}
}

func licenseFromURL(u string) domain.License {
	lu := strings.ToLower(u)
	switch {
	case strings.Contains(lu, "publicdomain") || strings.Contains(lu, "zero/1.0"):
		return domain.License{Code: "CC0", Name: "Public Domain / CC0", URL: u}
	case strings.Contains(lu, "by-sa"):
		return domain.License{Code: "CC-BY-SA", Name: "Creative Commons BY-SA", URL: u}
	case strings.Contains(lu, "by-nc"):
		return domain.License{Code: "CC-BY-NC", Name: "Creative Commons BY-NC", URL: u}
	case strings.Contains(lu, "by-nd"):
		return domain.License{Code: "CC-BY-ND", Name: "Creative Commons BY-ND", URL: u}
	case strings.Contains(lu, "creativecommons.org/licenses/by"):
		return domain.License{Code: "CC-BY", Name: "Creative Commons BY", URL: u}
	case strings.Contains(lu, "creativecommons"):
		return domain.License{Code: "CC", Name: "Creative Commons", URL: u}
	default:
		return domain.License{Code: "UNKNOWN", Name: "Unknown", URL: u}
	}
}

func creatorString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case []any:
		parts := make([]string, 0, len(x))
		for _, p := range x {
			if s, ok := p.(string); ok {
				parts = append(parts, s)
			}
		}
		return strings.Join(parts, ", ")
	default:
		return ""
	}
}

func firstNonEmpty(s ...string) string {
	for _, v := range s {
		if v != "" {
			return v
		}
	}
	return ""
}
