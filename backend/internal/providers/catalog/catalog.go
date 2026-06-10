// Package catalog implements the built-in MusicProvider backed by the
// local SQLite catalog. This is the "official" provider for tracks the
// Librefy operator vetted as libre-licensed.
package catalog

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/librefy/librefy/backend/internal/domain"
	"github.com/librefy/librefy/backend/internal/service"
)

// Provider is the local-catalog implementation of service.MusicProvider.
type Provider struct {
	db *sql.DB
}

// New constructs a catalog Provider backed by the given DB.
func New(db *sql.DB) *Provider { return &Provider{db: db} }

// Name implements service.MusicProvider.
func (p *Provider) Name() string { return "catalog" }

// Search implements service.MusicProvider with a simple LIKE-based scan.
// FTS5 can be wired in later without changing the interface.
func (p *Provider) Search(ctx context.Context, query string, limit int) (domain.SearchResult, error) {
	q := "%" + strings.ToLower(strings.TrimSpace(query)) + "%"
	rows, err := p.db.QueryContext(ctx, `
        SELECT id, title, artist, album, duration_ms, artwork_url,
               stream_url, magnet, info_hash,
               license_code, license_name, license_url, attribution,
               tags_json, provider, added_at
        FROM tracks
        WHERE LOWER(title) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ?
        ORDER BY added_at DESC
        LIMIT ?`, q, q, q, limit)
	if err != nil {
		return domain.SearchResult{}, err
	}
	defer rows.Close()

	tracks, err := scanTracks(rows)
	if err != nil {
		return domain.SearchResult{}, err
	}
	return domain.SearchResult{Tracks: tracks}, nil
}

// GetTrack implements service.MusicProvider.
func (p *Provider) GetTrack(ctx context.Context, id string) (domain.Track, error) {
	rows, err := p.db.QueryContext(ctx, `
        SELECT id, title, artist, album, duration_ms, artwork_url,
               stream_url, magnet, info_hash,
               license_code, license_name, license_url, attribution,
               tags_json, provider, added_at
        FROM tracks WHERE id = ? LIMIT 1`, id)
	if err != nil {
		return domain.Track{}, err
	}
	defer rows.Close()
	out, err := scanTracks(rows)
	if err != nil {
		return domain.Track{}, err
	}
	if len(out) == 0 {
		return domain.Track{}, service.ErrNotFound
	}
	return out[0], nil
}

// ResolveStream implements service.MusicProvider.
func (p *Provider) ResolveStream(ctx context.Context, id string) (service.StreamInfo, error) {
	t, err := p.GetTrack(ctx, id)
	if err != nil {
		return service.StreamInfo{}, err
	}
	info := service.StreamInfo{
		HTTPURL:  t.StreamURL,
		Magnet:   t.Magnet,
		InfoHash: t.InfoHash,
		MimeType: "audio/mpeg",
	}
	if info.HTTPURL == "" && info.Magnet == "" {
		return service.StreamInfo{}, errors.New("track has no playable source")
	}
	return info, nil
}
