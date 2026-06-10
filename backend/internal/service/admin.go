package service

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/librefy/librefy/backend/internal/domain"
)

// ErrConflict signals an attempt to insert a row whose primary key
// already exists. HTTP layer maps this to 409.
var ErrConflict = errors.New("conflict")

// ErrBadInput indicates malformed/invalid input. Maps to 400.
var ErrBadInput = errors.New("bad input")

// AdminListTracks returns ALL tracks (no provider-namespacing applied)
// for management UIs. Use Trending() for the public-facing list.
func (s *Service) AdminListTracks(ctx context.Context, limit, offset int) ([]domain.Track, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}
	rows, err := s.db.QueryContext(ctx, `
        SELECT id, title, artist, album, duration_ms, artwork_url,
               stream_url, magnet, info_hash,
               license_code, license_name, license_url, attribution,
               tags_json, provider, added_at
        FROM tracks
        ORDER BY added_at DESC
        LIMIT ? OFFSET ?`, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanTracks(rows)
}

// AdminListPlaylists returns all curated playlists.
func (s *Service) AdminListPlaylists(ctx context.Context) ([]domain.Playlist, error) {
	rows, err := s.db.QueryContext(ctx, `
        SELECT id, title, description, artwork_url, curated, updated_at
        FROM playlists
        ORDER BY updated_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []domain.Playlist
	for rows.Next() {
		var p domain.Playlist
		var description, artwork sql.NullString
		var curated int
		if err := rows.Scan(&p.ID, &p.Title, &description, &artwork, &curated, &p.UpdatedAt); err != nil {
			return nil, err
		}
		p.Description = description.String
		p.ArtworkURL = artwork.String
		p.Curated = curated == 1
		// Hydrate track IDs so the UI can drag-and-drop ordering.
		trackRows, err := s.db.QueryContext(ctx, `
            SELECT track_id FROM playlist_tracks
            WHERE playlist_id = ? ORDER BY position ASC`, p.ID)
		if err != nil {
			return nil, err
		}
		for trackRows.Next() {
			var tid string
			if err := trackRows.Scan(&tid); err != nil {
				_ = trackRows.Close()
				return nil, err
			}
			p.TrackIDs = append(p.TrackIDs, tid)
		}
		_ = trackRows.Close()
		out = append(out, p)
	}
	return out, rows.Err()
}

// AdminUpsertTrack inserts or replaces a track. The provider field is
// forced to "catalog" because external providers (ia, etc.) own their
// own IDs and must not be written through this API.
func (s *Service) AdminUpsertTrack(ctx context.Context, t domain.Track) error {
	if err := validateTrack(&t); err != nil {
		return err
	}
	t.Provider = "catalog"
	if t.AddedAt.IsZero() {
		t.AddedAt = time.Now().UTC()
	}
	tags, _ := json.Marshal(t.Tags)
	_, err := s.db.ExecContext(ctx, `
        INSERT INTO tracks (
            id, title, artist, album, duration_ms, artwork_url,
            stream_url, magnet, info_hash,
            license_code, license_name, license_url, attribution,
            tags_json, provider, added_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,
            artist=excluded.artist,
            album=excluded.album,
            duration_ms=excluded.duration_ms,
            artwork_url=excluded.artwork_url,
            stream_url=excluded.stream_url,
            magnet=excluded.magnet,
            info_hash=excluded.info_hash,
            license_code=excluded.license_code,
            license_name=excluded.license_name,
            license_url=excluded.license_url,
            attribution=excluded.attribution,
            tags_json=excluded.tags_json
    `,
		t.ID, t.Title, t.Artist, t.Album, t.DurationMS, t.ArtworkURL,
		t.StreamURL, t.Magnet, t.InfoHash,
		t.License.Code, t.License.Name, t.License.URL, t.Attribution,
		string(tags), t.Provider, t.AddedAt,
	)
	return err
}

// AdminDeleteTrack removes a track and detaches it from any playlists.
// Returns ErrNotFound if the track ID does not exist.
func (s *Service) AdminDeleteTrack(ctx context.Context, id string) error {
	// Strip the optional "catalog:" prefix that the admin UI might pass.
	id = strings.TrimPrefix(id, "catalog:")
	res, err := s.db.ExecContext(ctx, `DELETE FROM tracks WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// AdminUpsertPlaylist inserts/updates a playlist and (atomically)
// replaces its track list. The IDs in trackIDs may be either bare local
// IDs ("focus-cipher") or namespaced ("catalog:focus-cipher"); they are
// normalised to bare IDs for the FK constraint.
func (s *Service) AdminUpsertPlaylist(ctx context.Context, p domain.Playlist, trackIDs []string) error {
	if strings.TrimSpace(p.ID) == "" || strings.TrimSpace(p.Title) == "" {
		return fmt.Errorf("%w: id and title required", ErrBadInput)
	}
	if p.UpdatedAt.IsZero() {
		p.UpdatedAt = time.Now().UTC()
	}
	curated := 0
	if p.Curated {
		curated = 1
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	if _, err := tx.ExecContext(ctx, `
        INSERT INTO playlists (id, title, description, artwork_url, curated, updated_at)
        VALUES (?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            title=excluded.title,
            description=excluded.description,
            artwork_url=excluded.artwork_url,
            curated=excluded.curated,
            updated_at=excluded.updated_at
    `, p.ID, p.Title, p.Description, p.ArtworkURL, curated, p.UpdatedAt); err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `DELETE FROM playlist_tracks WHERE playlist_id = ?`, p.ID); err != nil {
		return err
	}
	for pos, raw := range trackIDs {
		tid := strings.TrimPrefix(strings.TrimSpace(raw), "catalog:")
		if tid == "" {
			continue
		}
		if _, err := tx.ExecContext(ctx, `
            INSERT INTO playlist_tracks (playlist_id, track_id, position)
            VALUES (?,?,?)`, p.ID, tid, pos); err != nil {
			return fmt.Errorf("link track %q: %w", tid, err)
		}
	}
	return tx.Commit()
}

// AdminDeletePlaylist drops the playlist row; the cascade clears its links.
func (s *Service) AdminDeletePlaylist(ctx context.Context, id string) error {
	id = strings.TrimPrefix(id, "catalog:")
	res, err := s.db.ExecContext(ctx, `DELETE FROM playlists WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// AdminExportSeed serialises the entire catalog into the same JSON
// shape that backend/internal/db/seed/tracks.json uses, so an operator
// can commit their changes back to git.
func (s *Service) AdminExportSeed(ctx context.Context) ([]byte, error) {
	tracks, err := s.AdminListTracks(ctx, 500, 0)
	if err != nil {
		return nil, err
	}
	playlists, err := s.AdminListPlaylists(ctx)
	if err != nil {
		return nil, err
	}
	payload := map[string]any{
		"tracks":    tracks,
		"playlists": playlists,
	}
	return json.MarshalIndent(payload, "", "  ")
}

// AdminStats returns lightweight counters for the dashboard.
func (s *Service) AdminStats(ctx context.Context) (map[string]int, error) {
	out := map[string]int{}
	for _, q := range []struct {
		key, sql string
	}{
		{"tracks", "SELECT COUNT(*) FROM tracks"},
		{"playlists", "SELECT COUNT(*) FROM playlists"},
		{"playlistLinks", "SELECT COUNT(*) FROM playlist_tracks"},
		{"plays", "SELECT COALESCE(SUM(play_count), 0) FROM track_stats"},
	} {
		var n int
		if err := s.db.QueryRowContext(ctx, q.sql).Scan(&n); err != nil {
			return nil, err
		}
		out[q.key] = n
	}
	return out, nil
}

// validateTrack enforces the libre-only invariants of the official build.
func validateTrack(t *domain.Track) error {
	if strings.TrimSpace(t.ID) == "" {
		return fmt.Errorf("%w: id required", ErrBadInput)
	}
	if strings.TrimSpace(t.Title) == "" {
		return fmt.Errorf("%w: title required", ErrBadInput)
	}
	if strings.TrimSpace(t.Artist) == "" {
		return fmt.Errorf("%w: artist required", ErrBadInput)
	}
	if strings.TrimSpace(t.License.Code) == "" {
		return fmt.Errorf("%w: license.code required (e.g. CC-BY-4.0, CC0)", ErrBadInput)
	}
	if strings.TrimSpace(t.StreamURL) == "" && strings.TrimSpace(t.Magnet) == "" {
		return fmt.Errorf("%w: at least one of streamUrl or magnet required", ErrBadInput)
	}
	return nil
}
