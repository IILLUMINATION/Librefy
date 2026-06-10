-- file_index lets multiple track rows share one magnet/info-hash while
-- pointing at distinct audio files inside the torrent (compilations,
-- multi-track albums, podcast feeds…).
-- 0 = "first audio file" (same as the existing single-track behaviour),
-- so the default is safe for every row already in the catalog.

ALTER TABLE tracks ADD COLUMN file_index INTEGER NOT NULL DEFAULT 0;
