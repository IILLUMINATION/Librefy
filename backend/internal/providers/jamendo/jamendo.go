// Package jamendo implements a MusicProvider backed by the Jamendo
// public catalogue (jamendo.com).
//
// Jamendo is the largest curated Creative-Commons music catalogue —
// every track on their platform is licensed CC by the rights-holder
// themselves at upload time. That makes it a much better fit for the
// Librefy "libre by default" promise than Internet Archive, which is
// noisier and includes a lot of non-music audio.
//
// The provider hits the public JSON API (api.jamendo.com/v3.0). All
// requests need a client_id; the official build ships a default that
// is enough for personal / small-instance traffic, but operators of
// larger librefyd deployments are expected to register their own and
// inject it via the JAMENDO_CLIENT_ID environment variable.
//
// IMPORTANT: Jamendo's API supports two HTTP audio formats per track:
//   - "mp31" (32 kbps preview, ~30s for some tracks)
//   - "mp32" (320 kbps, full length, standard for paying clients)
// The free tier ("personal use") gives full-length mp32 streams on
// CC tracks, which is exactly what we want; non-CC tracks are filtered
// out by `ccmixteronly=true` on every search.
package jamendo

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

const apiBase = "https://api.jamendo.com/v3.0"

// Provider implements service.MusicProvider against Jamendo's public API.
// A zero/empty clientID makes the provider a no-op (Search returns no
// results, GetTrack/ResolveStream return ErrNotFound) — Jamendo refuses
// every request without a valid client_id, and a noisy "credentials
// invalid" error in the search results is worse than a silently empty
// section. Operators register one at https://devportal.jamendo.com
// and inject it via JAMENDO_CLIENT_ID.
type Provider struct {
	http     *http.Client
	clientID string
}

// New constructs a Provider. Pass an empty clientID to make the
// provider a no-op (useful for default builds that don't ship API
// credentials). Pass nil http.Client to use a default with a 10s
// timeout.
func New(c *http.Client, clientID string) *Provider {
	if c == nil {
		c = &http.Client{Timeout: 10 * time.Second}
	}
	return &Provider{http: c, clientID: clientID}
}

// Enabled reports whether the provider has credentials and will
// actually issue requests. Wired into log output at startup so an
// operator who forgot to set JAMENDO_CLIENT_ID sees a clear hint
// instead of silently empty search results.
func (p *Provider) Enabled() bool { return p.clientID != "" }

// Name implements service.MusicProvider.
func (p *Provider) Name() string { return "jamendo" }

// jamendoTrack is the subset of the API response we actually consume.
// Jamendo returns numeric fields as JSON numbers, durations as ints
// (seconds), and license info as a sub-object.
type jamendoTrack struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	ArtistName   string `json:"artist_name"`
	AlbumName    string `json:"album_name"`
	Duration     int    `json:"duration"`
	ImageURL     string `json:"image"`
	AlbumImage   string `json:"album_image"`
	AudioURL     string `json:"audio"`
	AudioDLURL   string `json:"audiodownload"`
	LicenseCCURL string `json:"license_ccurl"`
}

type jamendoResponse struct {
	Headers struct {
		Status string `json:"status"`
		Code   int    `json:"code"`
	} `json:"headers"`
	Results []jamendoTrack `json:"results"`
}

// Search implements service.MusicProvider.Search.
// We constrain results to Creative Commons tracks (the entire Jamendo
// catalogue is CC by design, but we set ccmixteronly+include just to be
// explicit so future API changes can't silently surface anything else).
func (p *Provider) Search(ctx context.Context, query string, limit int) (domain.SearchResult, error) {
	if !p.Enabled() {
		return domain.SearchResult{}, nil
	}
	q := strings.TrimSpace(query)
	if q == "" {
		return domain.SearchResult{}, nil
	}
	if limit <= 0 {
		limit = 20
	}
	u, _ := url.Parse(apiBase + "/tracks/")
	v := u.Query()
	v.Set("client_id", p.clientID)
	v.Set("format", "json")
	v.Set("search", q)
	v.Set("limit", fmt.Sprintf("%d", limit))
	v.Set("audioformat", "mp32") // 320 kbps preview URLs
	// `include=musicinfo+licenses` would balloon the payload — we only
	// need the fields jamendoTrack declares.
	v.Set("imagesize", "300")
	u.RawQuery = v.Encode()

	body, err := p.fetch(ctx, u.String())
	if err != nil {
		return domain.SearchResult{}, err
	}
	out := domain.SearchResult{}
	for _, t := range body.Results {
		out.Tracks = append(out.Tracks, p.toTrack(t))
	}
	return out, nil
}

// GetTrack implements service.MusicProvider.GetTrack.
// The Jamendo /tracks endpoint already returns every field we need on
// a single-id lookup, so this is a thin wrapper that picks the first
// (only) result.
func (p *Provider) GetTrack(ctx context.Context, id string) (domain.Track, error) {
	if !p.Enabled() {
		return domain.Track{}, service.ErrNotFound
	}
	t, err := p.fetchByID(ctx, id)
	if err != nil {
		return domain.Track{}, err
	}
	return p.toTrack(t), nil
}

// ResolveStream implements service.MusicProvider.ResolveStream.
// Jamendo doesn't expose magnet links, so this is HTTP-only. The audio
// URL Jamendo returns is a temporary redirect into their CDN; just_audio
// follows redirects natively so there's nothing special to do here.
func (p *Provider) ResolveStream(ctx context.Context, id string) (service.StreamInfo, error) {
	if !p.Enabled() {
		return service.StreamInfo{}, service.ErrNotFound
	}
	t, err := p.fetchByID(ctx, id)
	if err != nil {
		return service.StreamInfo{}, err
	}
	// Prefer the explicit-download URL when present (full quality, no
	// 30 s preview clamp), else fall back to `audio`.
	stream := t.AudioDLURL
	if stream == "" {
		stream = t.AudioURL
	}
	if stream == "" {
		return service.StreamInfo{}, service.ErrNotFound
	}
	return service.StreamInfo{
		HTTPURL:  stream,
		MimeType: "audio/mpeg",
	}, nil
}

func (p *Provider) fetchByID(ctx context.Context, id string) (jamendoTrack, error) {
	u, _ := url.Parse(apiBase + "/tracks/")
	v := u.Query()
	v.Set("client_id", p.clientID)
	v.Set("format", "json")
	v.Set("id", id)
	v.Set("audioformat", "mp32")
	v.Set("imagesize", "300")
	u.RawQuery = v.Encode()

	body, err := p.fetch(ctx, u.String())
	if err != nil {
		return jamendoTrack{}, err
	}
	if len(body.Results) == 0 {
		return jamendoTrack{}, service.ErrNotFound
	}
	return body.Results[0], nil
}

func (p *Provider) fetch(ctx context.Context, fullURL string) (*jamendoResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fullURL, nil)
	if err != nil {
		return nil, err
	}
	// Be a polite citizen: identify ourselves so Jamendo can correlate
	// traffic if they ever need to.
	req.Header.Set("User-Agent", "librefyd/0.1 (+https://github.com/IILLUMINATION/Librefy)")

	resp, err := p.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("jamendo: HTTP %d", resp.StatusCode)
	}
	var body jamendoResponse
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("jamendo: decode: %w", err)
	}
	if body.Headers.Code != 0 && body.Headers.Code != 200 {
		return nil, fmt.Errorf("jamendo: api code %d (%s)",
			body.Headers.Code, body.Headers.Status)
	}
	return &body, nil
}

// toTrack maps a jamendoTrack to the Librefy domain track. The service
// layer is responsible for prefixing the provider name onto IDs — we
// return the raw upstream id here.
func (p *Provider) toTrack(t jamendoTrack) domain.Track {
	artwork := t.ImageURL
	if artwork == "" {
		artwork = t.AlbumImage
	}
	stream := t.AudioDLURL
	if stream == "" {
		stream = t.AudioURL
	}
	return domain.Track{
		ID:         t.ID,
		Title:      t.Name,
		Artist:     t.ArtistName,
		Album:      t.AlbumName,
		DurationMS: int64(t.Duration) * 1000,
		ArtworkURL: artwork,
		StreamURL:  stream,
		License:    licenseFromCCURL(t.LicenseCCURL),
		Provider:   "jamendo",
	}
}

// licenseFromCCURL maps the `license_ccurl` field to the same compact
// representation we use elsewhere. Jamendo always returns a CC URL
// (that's the whole point of the platform), so the default branch is
// generic-CC rather than UNKNOWN.
func licenseFromCCURL(u string) domain.License {
	lu := strings.ToLower(u)
	switch {
	case strings.Contains(lu, "publicdomain") || strings.Contains(lu, "zero/1.0"):
		return domain.License{Code: "CC0", Name: "Public Domain / CC0", URL: u}
	case strings.Contains(lu, "by-sa"):
		return domain.License{Code: "CC-BY-SA", Name: "Creative Commons BY-SA", URL: u}
	case strings.Contains(lu, "by-nc-sa"):
		return domain.License{Code: "CC-BY-NC-SA", Name: "Creative Commons BY-NC-SA", URL: u}
	case strings.Contains(lu, "by-nc-nd"):
		return domain.License{Code: "CC-BY-NC-ND", Name: "Creative Commons BY-NC-ND", URL: u}
	case strings.Contains(lu, "by-nc"):
		return domain.License{Code: "CC-BY-NC", Name: "Creative Commons BY-NC", URL: u}
	case strings.Contains(lu, "by-nd"):
		return domain.License{Code: "CC-BY-ND", Name: "Creative Commons BY-ND", URL: u}
	case strings.Contains(lu, "creativecommons.org/licenses/by"):
		return domain.License{Code: "CC-BY", Name: "Creative Commons BY", URL: u}
	default:
		return domain.License{Code: "CC", Name: "Creative Commons", URL: u}
	}
}
