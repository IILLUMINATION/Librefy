# Librefy — Architecture

## Goals

- **Privacy-first**: no accounts, no telemetry, no user-tied analytics.
- **Lightweight backend**: metadata only, never an audio CDN.
- **Decentralised delivery**: P2P/torrent is the primary transport
  whenever a magnet is available; HTTP is the fallback.
- **Modular providers**: the catalog is the union of pluggable
  `MusicProvider`s. The official build only registers libre-safe ones.
- **Cross-platform**: Android first, Linux desktop next, more later.

## High-level data flow

```
       ┌──────────────────────┐                      ┌────────────────────┐
       │  Flutter app         │  HTTP /api/v1/...    │  librefyd (Go)     │
       │                      │  ──────────────────▶ │  chi + SQLite      │
       │  Riverpod state      │                      │                    │
       │  just_audio          │                      │  ┌──────────────┐  │
       │                      │                      │  │ Catalog      │  │
       │  SourceResolver      │                      │  │ provider     │  │
       │   ├─ HTTP fallback   │                      │  ├──────────────┤  │
       │   └─ TorrentService  │                      │  │ Internet     │  │
       │       (libtorrent)   │                      │  │ Archive prov │  │
       └────────────┬─────────┘                      │  ├──────────────┤  │
                    │                                │  │ (community   │  │
                    │ Magnet / HTTP                  │  │  plugins)    │  │
                    ▼                                │  └──────────────┘  │
            ┌───────────────┐                        └────────────────────┘
            │ Peer swarm OR │
            │ origin server │
            └───────────────┘
```

The backend never streams audio bytes. It returns:

- track metadata (`title`, `artist`, `licence`, `attribution`, ...),
- a `httpUrl` (HTTP fallback origin, **must** be libre-licensed),
- optionally a `magnet` URI for peer-assisted delivery.

The app's `SourceResolver` picks the best available transport.

## Backend (Go)

```
backend/
├── cmd/librefyd/         # main entry point
├── internal/
│   ├── config/           # env-driven config (LIBREFY_ADDR, LIBREFY_DB, ...)
│   ├── db/               # SQLite open + migrate + seed
│   │   ├── migrations/   # embedded SQL (//go:embed migrations/*.sql)
│   │   └── seed/         # embedded JSON catalog (//go:embed seed/tracks.json)
│   ├── domain/           # transport-agnostic models
│   ├── service/          # ProviderRegistry, Search/GetTrack/ResolveStream
│   ├── providers/
│   │   ├── catalog/      # local-DB-backed MusicProvider
│   │   └── ia/           # Internet Archive MusicProvider
│   └── http/             # chi router + JSON handlers
```

### Seed strategy

The default catalog is a JSON file (`backend/internal/db/seed/tracks.json`)
embedded into the Go binary via `//go:embed`. On first boot the backend
loads it into SQLite once; from then on every read goes through indexed
SQL queries — JSON is never touched at runtime.

Operators can override the embedded seed at runtime:

```bash
LIBREFY_SEED=/path/to/my-tracks.json librefyd
```

JSON is used because:

- The file is hand-edited (to drop in magnet URIs and attribution strings)
  more often than it's generated, and JSON is friendlier than escaped SQL.
- The schema is type-checked against `domain.Track` at compile time.
- Loading 5–500 rows is a one-time millisecond-scale operation.

When/if the catalog grows past ~100k items we'll switch to either an
`.sql` seed or a pre-built SQLite snapshot file.

### MusicProvider contract (Go)

```go
type MusicProvider interface {
    Name() string
    Search(ctx, query, limit)  (SearchResult, error)
    GetTrack(ctx, id)          (Track, error)
    ResolveStream(ctx, id)     (StreamInfo, error)
}
```

The same shape is mirrored in the Flutter `domain/providers/music_provider.dart`.

### REST API (v1)

| Method | Path | Purpose |
|--------|------|---------|
| GET  | `/api/v1/health` | service health |
| GET  | `/api/v1/featured?limit=` | curated playlists |
| GET  | `/api/v1/trending?limit=` | most-played local tracks |
| GET  | `/api/v1/search?q=&limit=` | fan-out search across providers |
| GET  | `/api/v1/tracks/{id}` | track metadata (id = `provider:localId`) |
| GET  | `/api/v1/tracks/{id}/stream` | resolve to HTTP + magnet |
| POST | `/api/v1/tracks/{id}/play` | anonymous play counter |
| GET  | `/api/v1/playlists/{id}` | playlist + tracks |

### Database schema

See `backend/internal/db/migrations/0001_init.sql`.
Key tables: `tracks`, `playlists`, `playlist_tracks`, `track_stats`.
Licence data is inlined into `tracks` (denormalised; licences are
small, immutable strings).

## App (Flutter)

```
app/lib/
├── main.dart                      # MaterialApp + dynamic colour + background audio
├── core/
│   ├── theme/librefy_theme.dart   # MD3 themes (light/dark)
│   ├── router/app_router.dart     # go_router
│   ├── network/api_config.dart    # base-URL resolution
│   └── error/failures.dart        # Failure taxonomy
├── domain/                        # Pure Dart, no Flutter imports
│   ├── entities/                  # Track, Playlist, StreamInfo, License, ...
│   ├── providers/                 # MusicProvider interface (mirror of backend)
│   └── repositories/              # CatalogRepository interface
├── data/
│   ├── models/                    # JSON DTOs ↔ domain mapping (hand-written)
│   ├── datasources/librefy_api.dart  # Dio client
│   └── repositories/              # CatalogRepositoryImpl
├── application/
│   ├── state/providers.dart       # Riverpod providers (repo, search, recent)
│   ├── audio/                     # AudioPlayerService + Riverpod wiring
│   ├── cache/audio_cache.dart     # On-disk LRU cache (data plane)
│   └── torrent/
│       ├── torrent_service.dart   # Interface + HttpOnlyTorrentService stub
│       └── source_resolver.dart   # Picks magnet vs HTTP
└── presentation/
    ├── common/                    # AppShell, MiniPlayer, Artwork
    ├── home/                      # Featured + trending + recent
    ├── search/                    # Debounced search
    ├── player/now_playing_screen.dart
    ├── library/                   # Recently played, playlist detail
    └── settings/                  # Minimal settings surface
```

### State management

Riverpod is used **without** code-gen to keep the MVP free of
build_runner. Providers are tiny and single-purpose:

- `catalogRepositoryProvider` — composition root.
- `featuredPlaylistsProvider`, `trendingTracksProvider` — `FutureProvider`s.
- `searchQueryProvider` + `searchResultsProvider` — debounced search.
- `audioPlayerServiceProvider` + `playbackSnapshotProvider` — playback.
- `recentlyPlayedProvider` — `StateNotifierProvider` (in-memory MVP).

### Audio pipeline

`just_audio` ↔ `AudioPlayerService` ↔ `SourceResolver` ↔ `TorrentService`.

`SourceResolver.resolve(StreamInfo)`:

1. If a magnet is available **and** the torrent service supports peer delivery,
   open the swarm and return its local HTTP proxy URI.
2. Otherwise fall back to the libre HTTP URL returned by the backend.

`just_audio` only ever sees a normal URI — it has no idea P2P exists.

### TorrentService design

The interface intentionally exposes a `Uri` (not a stream of bytes) so the
native engine is free to run an internal HTTP/Unix-socket proxy and let
the audio player consume audio progressively. Two implementations are
expected:

1. **HttpOnlyTorrentService** (ships in MVP, default in official build).
   Reports `supportsPeerDelivery == false`; the resolver always falls
   back to the HTTP URL.
2. **LibtorrentService** (separate package, not shipped officially).
   Wraps `libtorrent` via `dart:ffi`; runs a local HTTP server that
   serves progressive pieces. Must be installed explicitly by users
   who understand the responsibilities involved.

## Provider extensibility

Third-party providers are not loaded by the official app build. The
contract exists so that:

- Self-hosted users can compile a custom build that registers
  additional providers under their own responsibility.
- The community can publish provider packages independently of the
  official repository.

Anything that surfaces non-libre content **must not** be merged into
the official catalog or default provider list.

## Privacy-first defaults

- No accounts, no auth in MVP.
- The only data the backend stores about playback is an **anonymous,
  aggregate** play counter per track.
- Recently-played is **on-device only** and never sent anywhere.
- No third-party analytics or crash-reporting SDKs are included.
