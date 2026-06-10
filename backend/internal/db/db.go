// Package db owns the SQLite connection, schema and seeding logic.
//
// We use modernc.org/sqlite (pure-Go) so the backend cross-compiles
// trivially for Linux desktop and small servers without cgo.
package db

import (
	"database/sql"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"sort"
	"strings"

	_ "modernc.org/sqlite"

	"github.com/librefy/librefy/backend/internal/domain"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// embeddedSeed is the default catalog shipped with the binary. It lets
// librefyd boot with a non-empty catalog from any working directory and
// keeps deployment to a "scp the binary and run it" affair. Operators
// can override it by setting LIBREFY_SEED to an external JSON file.
//
//go:embed seed/tracks.json
var embeddedSeed []byte

// Open opens (and creates if necessary) the SQLite database at path.
func Open(path string) (*sql.DB, error) {
	dsn := fmt.Sprintf("file:%s?_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)", path)
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	if err := conn.Ping(); err != nil {
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}
	// SQLite + WAL works best with a small pool.
	conn.SetMaxOpenConns(1)
	return conn, nil
}

// Migrate applies embedded SQL migrations in lexical order, tracking
// which ones have already run via the schema_migrations bookkeeping
// table. Each migration runs at most once per database; idempotent
// across restarts.
func Migrate(conn *sql.DB) error {
	// Bootstrap the bookkeeping table. We can't put this in a regular
	// migration file because we'd need it before we can track migrations.
	if _, err := conn.Exec(`
        CREATE TABLE IF NOT EXISTS schema_migrations (
            name       TEXT PRIMARY KEY,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )`); err != nil {
		return fmt.Errorf("bootstrap migrations: %w", err)
	}

	entries, err := fs.ReadDir(migrationsFS, "migrations")
	if err != nil {
		return fmt.Errorf("read migrations: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	applied, err := loadAppliedMigrations(conn)
	if err != nil {
		return err
	}

	for _, name := range names {
		if applied[name] {
			continue
		}
		body, err := fs.ReadFile(migrationsFS, "migrations/"+name)
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}
		if _, err := conn.Exec(string(body)); err != nil {
			return fmt.Errorf("apply %s: %w", name, err)
		}
		if _, err := conn.Exec(
			`INSERT INTO schema_migrations(name) VALUES (?)`, name,
		); err != nil {
			return fmt.Errorf("record %s: %w", name, err)
		}
		slog.Info("migration applied", "file", name)
	}
	return nil
}

func loadAppliedMigrations(conn *sql.DB) (map[string]bool, error) {
	out := map[string]bool{}
	rows, err := conn.Query(`SELECT name FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("load applied: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		out[n] = true
	}
	// Backfill: if the catalog table already exists but the bookkeeping
	// is empty, the DB was created before this tracker was added — mark
	// the initial migration as applied so we don't try to re-create
	// existing tables (CREATE IF NOT EXISTS would be silent, but adding
	// columns isn't). The presence of `tracks` indicates a v0.1 DB.
	if len(out) == 0 {
		var hasTracks int
		_ = conn.QueryRow(
			`SELECT 1 FROM sqlite_master WHERE type='table' AND name='tracks'`,
		).Scan(&hasTracks)
		if hasTracks == 1 {
			_, _ = conn.Exec(
				`INSERT INTO schema_migrations(name) VALUES ('0001_init.sql')`)
			out["0001_init.sql"] = true
			// If the column already exists too, the v0.2 migration is a no-op
			// but we still need to mark it as applied to be idempotent on
			// next boots.
			var hasFileIndex int
			_ = conn.QueryRow(
				`SELECT 1 FROM pragma_table_info('tracks') WHERE name='file_index'`,
			).Scan(&hasFileIndex)
			if hasFileIndex == 1 {
				_, _ = conn.Exec(
					`INSERT INTO schema_migrations(name) VALUES ('0002_file_index.sql')`)
				out["0002_file_index.sql"] = true
			}
		}
	}
	return out, nil
}

// SeedIfEmpty loads tracks/playlists into the catalog when the tracks
// table is empty.
//
// Resolution order:
//  1. If overridePath != "" and the file exists → load from disk.
//     This is for operators who want to ship their own catalog without
//     recompiling the binary (LIBREFY_SEED env var).
//  2. Otherwise → load the embedded seed compiled into the binary.
//
// The seed MUST only contain libre-licensed tracks. After seeding, if
// the catalog is somehow still empty (parse error, empty seed), we log
// a warning so the operator notices.
func SeedIfEmpty(conn *sql.DB, overridePath string) error {
	var n int
	if err := conn.QueryRow("SELECT COUNT(1) FROM tracks").Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return nil
	}

	raw, source, err := resolveSeed(overridePath)
	if err != nil {
		return err
	}
	if len(raw) == 0 {
		slog.Warn("catalog is empty and no seed available; the app will show empty home screen")
		return nil
	}

	var seed struct {
		Tracks    []domain.Track    `json:"tracks"`
		Playlists []domain.Playlist `json:"playlists"`
	}
	if err := json.Unmarshal(raw, &seed); err != nil {
		return fmt.Errorf("parse seed (%s): %w", source, err)
	}

	tx, err := conn.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	for _, t := range seed.Tracks {
		if err := insertTrack(tx, t); err != nil {
			return fmt.Errorf("insert track %s: %w", t.ID, err)
		}
	}
	for _, p := range seed.Playlists {
		if err := insertPlaylist(tx, p); err != nil {
			return fmt.Errorf("insert playlist %s: %w", p.ID, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return err
	}
	slog.Info("catalog seeded",
		"source", source,
		"tracks", len(seed.Tracks),
		"playlists", len(seed.Playlists))
	return nil
}

// resolveSeed returns (bytes, source-name) using the override path when
// available, otherwise falling back to the embedded seed.
func resolveSeed(overridePath string) ([]byte, string, error) {
	if overridePath != "" {
		raw, err := os.ReadFile(overridePath)
		if err == nil {
			return raw, overridePath, nil
		}
		if !os.IsNotExist(err) {
			return nil, "", fmt.Errorf("read seed %s: %w", overridePath, err)
		}
		slog.Info("override seed not found; using embedded", "path", overridePath)
	}
	return embeddedSeed, "embedded", nil
}

func insertTrack(tx *sql.Tx, t domain.Track) error {
	tags, _ := json.Marshal(t.Tags)
	_, err := tx.Exec(`
        INSERT INTO tracks (
            id, title, artist, album, duration_ms, artwork_url,
            stream_url, magnet, info_hash, file_index,
            license_code, license_name, license_url, attribution,
            tags_json, provider, added_at
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, COALESCE(?, CURRENT_TIMESTAMP))
    `,
		t.ID, t.Title, t.Artist, t.Album, t.DurationMS, t.ArtworkURL,
		t.StreamURL, t.Magnet, t.InfoHash, t.FileIndex,
		t.License.Code, t.License.Name, t.License.URL, t.Attribution,
		string(tags), t.Provider, nullableTime(t.AddedAt),
	)
	return err
}

func insertPlaylist(tx *sql.Tx, p domain.Playlist) error {
	if _, err := tx.Exec(`
        INSERT INTO playlists (id, title, description, artwork_url, curated, updated_at)
        VALUES (?,?,?,?,?, COALESCE(?, CURRENT_TIMESTAMP))
    `, p.ID, p.Title, p.Description, p.ArtworkURL, p.Curated, nullableTime(p.UpdatedAt)); err != nil {
		return err
	}
	for pos, trackID := range p.TrackIDs {
		if _, err := tx.Exec(`
            INSERT INTO playlist_tracks (playlist_id, track_id, position)
            VALUES (?,?,?)
        `, p.ID, trackID, pos); err != nil {
			return err
		}
	}
	return nil
}

func nullableTime(t interface{ IsZero() bool }) any {
	if t.IsZero() {
		return nil
	}
	return t
}
