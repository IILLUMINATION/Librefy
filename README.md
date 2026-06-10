# Librefy

**Privacy-first, libre / free music streaming with peer-assisted delivery.**

Librefy is an open-source music app inspired by Spotify but built around
a totally different premise: only **legally redistributable** music
(Creative Commons, CC0, public-domain, royalty-free, artist-released)
is ever streamed by the official build. There are no ads, no tracking,
no accounts, and the backend is intentionally tiny — heavy audio
traffic is meant to be offloaded to peer-assisted (torrent / WebTorrent)
delivery once the operator opts in.

> Librefy is **not** a piracy tool. The official catalog and the
> reference build do **not** index commercial copyrighted material and
> never will. Torrent is used purely as a delivery technology, not as a
> content-sourcing technology. See [`docs/LEGAL.md`](docs/LEGAL.md).

## Repository layout

```
Librefy/
├── backend/        # Go service (REST API, SQLite, providers)
├── app/            # Flutter app (Android + Linux desktop)
├── docs/           # Architecture & legal notes
└── scripts/        # Convenience scripts
```

## Quick start

### 1. Backend

```bash
./scripts/run-backend.sh
# listens on :8080, seeds SQLite from the embedded catalog on first run
```

Inside VS Code: `Ctrl+Shift+B` runs the same task (see `.vscode/tasks.json`).

Smoke-test:

```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/featured
curl "http://localhost:8080/api/v1/search?q=cipher"
```

### 2. App — Linux desktop

```bash
cd app
flutter pub get
flutter run -d linux
```

### 3. App — Android

```bash
cd app
flutter pub get
flutter run -d <your-device-or-emulator>
```

> On the Android emulator, the app talks to your host machine via
> `http://10.0.2.2:8080` automatically (see `lib/core/network/api_config.dart`).

## What's in the MVP

- Go backend (chi + SQLite) with metadata, search, playlists, license info, anonymous play counters.
- Built-in **Catalog** provider (curated libre tracks seeded from `backend/seed/tracks.json`).
- Built-in **Internet Archive** provider (libre-only filter on `archive.org`).
- Flutter app with Material 3, dynamic colour, navigation rail on desktop.
- `just_audio` playback with queue, background notifications, lockscreen controls (Android).
- On-device "Recently played" (privacy-first, never sent to the backend).
- `TorrentService` abstraction with a safe `HttpOnlyTorrentService` default. Wire libtorrent / WebTorrent in later without touching the player.

## Troubleshooting

### Home screen shows no tracks / "Catalog is empty"

1. Make sure the backend is running and listening on the expected URL
   (default `http://127.0.0.1:8080`).
2. Hit `http://127.0.0.1:8080/api/v1/trending` in your browser. You should
   see a JSON payload with a `"tracks": [...]` array.
3. If the array is empty, your `librefy.db` was created before the embedded
   seed was wired in. Delete it and restart the backend:

   ```bash
   # macOS/Linux — wipe any stale DB anywhere in the repo
   find . -maxdepth 4 -name 'librefy.db*' -delete
   ./scripts/run-backend.sh
   ```

   The VS Code task **"Librefy: Reset DB"** does the same.
4. In the app, tap **Retry** on the empty-catalog card or restart.

### Backend uses the wrong base URL

Set it at build time:

```bash
flutter run -d linux --dart-define=LIBREFY_API=http://your.host:8080
```

## Roadmap (not in MVP)

- libtorrent FFI integration (progressive streaming, fallback to HTTP).
- On-disk audio LRU cache wired into `just_audio` (data plane already in `lib/application/cache`).
- User playlists, sync (opt-in).
- External provider plugins.

## Licensing

Librefy itself is licensed under the **AGPL-3.0**. Every track in the
catalog ships with its own licence metadata; the UI exposes it on the
Now Playing screen.
