package service

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/librefy/librefy/backend/internal/domain"
)

// Service is the application-layer facade used by HTTP handlers.
// It fan-outs searches to providers, normalises IDs, and serves the
// local catalog (curated playlists, featured tracks, etc.).
type Service struct {
	providers *ProviderRegistry
	db        *sql.DB
}

// New constructs a Service.
func New(providers *ProviderRegistry, db *sql.DB) *Service {
	return &Service{providers: providers, db: db}
}

// Search queries every registered provider and merges their results.
// Each returned ID is namespaced as "<provider>:<localID>" so clients
// can later resolve streams against the correct provider.
func (s *Service) Search(ctx context.Context, query string, limit int) (domain.SearchResult, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	merged := domain.SearchResult{}
	for _, p := range s.providers.List() {
		// Bound the per-provider call so a slow upstream never stalls
		// the whole search.
		res, err := p.Search(ctx, query, limit)
		if err != nil {
			// Soft-fail individual providers — search degrades gracefully.
			continue
		}
		for _, t := range res.Tracks {
			t.ID = namespace(p.Name(), t.ID)
			t.Provider = p.Name()
			merged.Tracks = append(merged.Tracks, t)
		}
		for _, a := range res.Artists {
			a.ID = namespace(p.Name(), a.ID)
			merged.Artists = append(merged.Artists, a)
		}
		for _, pl := range res.Playlists {
			pl.ID = namespace(p.Name(), pl.ID)
			merged.Playlists = append(merged.Playlists, pl)
		}
	}
	return merged, nil
}

// GetTrack resolves a namespaced ID to the owning provider and returns
// the track with the namespaced ID restored.
func (s *Service) GetTrack(ctx context.Context, namespacedID string) (domain.Track, error) {
	prov, local, ok := splitNS(namespacedID)
	if !ok {
		return domain.Track{}, ErrNotFound
	}
	p, ok := s.providers.Get(prov)
	if !ok {
		return domain.Track{}, ErrNotFound
	}
	t, err := p.GetTrack(ctx, local)
	if err != nil {
		return domain.Track{}, err
	}
	t.ID = namespace(prov, t.ID)
	t.Provider = prov
	return t, nil
}

// ResolveStream returns delivery information for a track.
func (s *Service) ResolveStream(ctx context.Context, namespacedID string) (StreamInfo, error) {
	prov, local, ok := splitNS(namespacedID)
	if !ok {
		return StreamInfo{}, ErrNotFound
	}
	p, ok := s.providers.Get(prov)
	if !ok {
		return StreamInfo{}, ErrNotFound
	}
	return p.ResolveStream(ctx, local)
}

// Featured returns curated playlists from the local catalog. These are
// the entrypoints displayed on the app home screen.
func (s *Service) Featured(ctx context.Context, limit int) ([]domain.Playlist, error) {
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	rows, err := s.db.QueryContext(ctx, `
        SELECT id, title, description, artwork_url, curated, updated_at
        FROM playlists
        WHERE curated = 1
        ORDER BY updated_at DESC
        LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []domain.Playlist
	for rows.Next() {
		var p domain.Playlist
		var curated int
		if err := rows.Scan(&p.ID, &p.Title, &p.Description, &p.ArtworkURL, &curated, &p.UpdatedAt); err != nil {
			return nil, err
		}
		p.ID = namespace("catalog", p.ID)
		p.Curated = curated == 1
		out = append(out, p)
	}
	return out, rows.Err()
}

// Trending returns the most-played tracks of the local catalog.
// Falls back to most-recently-added when no plays have been recorded.
func (s *Service) Trending(ctx context.Context, limit int) ([]domain.Track, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows, err := s.db.QueryContext(ctx, `
        SELECT t.id, t.title, t.artist, t.album, t.duration_ms, t.artwork_url,
               t.stream_url, t.magnet, t.info_hash, t.file_index,
               t.license_code, t.license_name, t.license_url, t.attribution,
               t.tags_json, t.provider, t.added_at
        FROM tracks t
        LEFT JOIN track_stats s ON s.track_id = t.id
        ORDER BY COALESCE(s.play_count, 0) DESC, t.added_at DESC
        LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out, err := scanTracks(rows)
	if err != nil {
		return nil, err
	}
	for i := range out {
		out[i].ID = namespace("catalog", out[i].ID)
	}
	return out, nil
}

// RecordPlay anonymously increments the play counter for a track.
// It is best-effort and never blocks the audio path.
func (s *Service) RecordPlay(ctx context.Context, namespacedID string) error {
	prov, local, ok := splitNS(namespacedID)
	if !ok || prov != "catalog" {
		// Only count plays for the local catalog — we don't track usage
		// against third-party providers like the Internet Archive.
		return nil
	}
	_, err := s.db.ExecContext(ctx, `
        INSERT INTO track_stats (track_id, play_count) VALUES (?, 1)
        ON CONFLICT(track_id) DO UPDATE SET play_count = play_count + 1
    `, local)
	return err
}

// PlaylistTracks expands a curated playlist into its tracks.
func (s *Service) PlaylistTracks(ctx context.Context, namespacedID string) (domain.Playlist, []domain.Track, error) {
	prov, local, ok := splitNS(namespacedID)
	if !ok || prov != "catalog" {
		return domain.Playlist{}, nil, ErrNotFound
	}

	var p domain.Playlist
	var curated int
	err := s.db.QueryRowContext(ctx, `
        SELECT id, title, description, artwork_url, curated, updated_at
        FROM playlists WHERE id = ?`, local,
	).Scan(&p.ID, &p.Title, &p.Description, &p.ArtworkURL, &curated, &p.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Playlist{}, nil, ErrNotFound
	}
	if err != nil {
		return domain.Playlist{}, nil, err
	}
	p.Curated = curated == 1
	p.ID = namespace("catalog", p.ID)

	rows, err := s.db.QueryContext(ctx, `
        SELECT t.id, t.title, t.artist, t.album, t.duration_ms, t.artwork_url,
               t.stream_url, t.magnet, t.info_hash, t.file_index,
               t.license_code, t.license_name, t.license_url, t.attribution,
               t.tags_json, t.provider, t.added_at
        FROM tracks t
        JOIN playlist_tracks pt ON pt.track_id = t.id
        WHERE pt.playlist_id = ?
        ORDER BY pt.position ASC`, local)
	if err != nil {
		return p, nil, err
	}
	defer rows.Close()

	tracks, err := scanTracks(rows)
	if err != nil {
		return p, nil, err
	}
	for i := range tracks {
		tracks[i].ID = namespace("catalog", tracks[i].ID)
		p.TrackIDs = append(p.TrackIDs, tracks[i].ID)
	}
	return p, tracks, nil
}

func namespace(provider, id string) string {
	if strings.Contains(id, ":") {
		return id
	}
	return provider + ":" + id
}

func splitNS(id string) (provider, local string, ok bool) {
	i := strings.IndexByte(id, ':')
	if i <= 0 || i == len(id)-1 {
		return "", "", false
	}
	return id[:i], id[i+1:], true
}
