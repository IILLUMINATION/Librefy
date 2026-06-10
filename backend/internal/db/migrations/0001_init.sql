-- Librefy core schema.
-- Tracks reference license metadata inline (denormalised on purpose: licenses
-- are small, immutable strings and joining them on every search would be wasteful).

CREATE TABLE IF NOT EXISTS tracks (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    artist       TEXT NOT NULL,
    album        TEXT,
    duration_ms  INTEGER NOT NULL DEFAULT 0,
    artwork_url  TEXT,
    stream_url   TEXT,                  -- HTTP fallback origin (libre only)
    magnet       TEXT,                  -- magnet URI for peer-assisted delivery
    info_hash    TEXT,                  -- hex info-hash if known
    license_code TEXT NOT NULL,         -- "CC0", "CC-BY-4.0", "PD"...
    license_name TEXT NOT NULL,
    license_url  TEXT,
    attribution  TEXT,
    tags_json    TEXT NOT NULL DEFAULT '[]',
    provider     TEXT NOT NULL,         -- which provider owns this row
    added_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
CREATE INDEX IF NOT EXISTS idx_tracks_title  ON tracks(title);
CREATE INDEX IF NOT EXISTS idx_tracks_added  ON tracks(added_at DESC);

CREATE TABLE IF NOT EXISTS playlists (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT,
    artwork_url TEXT,
    curated     INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL,
    track_id    TEXT NOT NULL,
    position    INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, track_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (track_id)    REFERENCES tracks(id)    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlist_tracks_pos
    ON playlist_tracks(playlist_id, position);

-- Lightweight, anonymous play-count aggregation. Privacy-first:
-- we never store who played anything, only that *something* was played.
CREATE TABLE IF NOT EXISTS track_stats (
    track_id    TEXT PRIMARY KEY,
    play_count  INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
);
