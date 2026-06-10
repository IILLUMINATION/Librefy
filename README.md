# Librefy

**Privacy-first, libre / free music streaming with peer-assisted delivery.**

<p>
  <img alt="status" src="https://img.shields.io/badge/status-MVP-orange">
  <img alt="license" src="https://img.shields.io/badge/license-AGPL--3.0-blue">
  <img alt="backend" src="https://img.shields.io/badge/backend-Go%20%2B%20SQLite-00ADD8">
  <img alt="app" src="https://img.shields.io/badge/app-Flutter%20(Android%20%2B%20Linux)-02569B">
</p>

Librefy is an open-source music app inspired by Spotify but built around a
very different premise: only **legally redistributable** music
(Creative Commons, CC0, public-domain, royalty-free, artist-released)
is ever streamed by the official build. There are **no ads, no tracking,
no accounts**, and the backend is intentionally tiny — heavy audio traffic
is meant to be offloaded to peer-assisted (torrent / WebTorrent) delivery
once the operator opts in.

> Librefy is **not** a piracy tool. The official catalog and the reference
> build do **not** index commercial copyrighted material and never will.
> Torrent is used purely as a delivery technology, not as a content-sourcing
> technology. See [`docs/LEGAL.md`](docs/LEGAL.md).

## Demo backend

A small public catalog runs on `http://194.31.223.9:8088`. Release APK
builds talk to it by default; you can swap to your own server any time
from **Settings → Backend URL**, or follow the in-app guide to deploy
your own in ~10 minutes.

```bash
curl http://194.31.223.9:8088/api/v1/health
curl http://194.31.223.9:8088/api/v1/trending?limit=3
```

## Features (MVP)

- 🎵 Stream Creative Commons / public-domain music with per-track licence display
- 🎨 Material 3, dynamic colour, responsive (NavigationBar ↔ NavigationRail)
- 🔍 Debounced search across the local catalog and the Internet Archive
- 🌍 **True peer-assisted delivery** — magnet-linked tracks play directly
  from the BitTorrent swarm via an embedded native bridge (anacrolix/torrent
  + dart:ffi). Backend never proxies audio. See [`docs/P2P.md`](docs/P2P.md).
- 📱 In-app playback for Android & Linux desktop via media_kit
- 🧩 Pluggable provider system (`MusicProvider` interface, mirrored backend/app)
- 🛠️ Built-in admin web UI for managing tracks & playlists
- 🔒 Privacy-first: no accounts, no telemetry, anonymous-only play counters

## Repository layout

```
Librefy/
├── backend/         # Go service (REST API, SQLite, providers, admin UI)
├── app/             # Flutter app (Android + Linux desktop)
├── docs/            # ARCHITECTURE, LEGAL, DEPLOY
├── scripts/         # run-backend.sh, run-app-linux.sh, deploy.sh
└── .vscode/         # tasks & extension recommendations
```

## Quick start (development)

### Backend

```bash
./scripts/run-backend.sh
# Listens on :8080 with the embedded libre catalog already loaded.
```

VS Code: `Ctrl+Shift+B` runs the same task (see `.vscode/tasks.json`).

### Flutter app — Linux

```bash
./scripts/setup.sh           # one-shot: installs libmpv if missing
./scripts/build-native.sh    # build liblibrefy_torrent.so (~30s)
./scripts/run-app-linux.sh
```

> First run also invokes `setup.sh` for you if `libmpv` is missing.
> The native torrent bridge is optional — without it, magnet-only tracks
> show a friendly "P2P unavailable" snackbar and HTTP fallback streams
> still work.

### Flutter app — Android

```bash
./scripts/build-native-android.sh   # cross-compile native lib (~1 min)
cd app && flutter run -d <device>
```

Requires `ANDROID_NDK_HOME` (auto-detected at `~/Android/Sdk/ndk/<latest>`).

> Android emulator → `http://10.0.2.2:8080` is used automatically.

## Admin web UI

The backend ships with a small built-in admin panel. **It stays disabled
until you set a token** — that's the safe default for a fresh deploy.

```bash
LIBREFY_ADMIN_TOKEN=$(openssl rand -hex 32) ./scripts/run-backend.sh
# Open http://localhost:8080/admin/ and paste the token.
```

Features:

- Add / edit / delete tracks with full licence metadata, magnet URI,
  attribution, tags
- Manage curated playlists & ordering
- Bulk JSON import / export (round-trip with `seed/tracks.json`)
- Lightweight stats dashboard

## Deploying your own backend on a VPS

Either follow the **in-app guide** (Settings → "Deploy your own backend",
copy-buttoned step-by-step) or the [`docs/DEPLOY.md`](docs/DEPLOY.md)
walkthrough. Short version:

```bash
# 1. Build a static binary
cd backend
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags="-s -w" -o librefyd ./cmd/librefyd

# 2. Ship it
scp librefyd root@YOUR_VPS:/opt/librefy/

# 3. Run as systemd service (see docs/DEPLOY.md for the unit file)
```

Or use the helper:

```bash
VPS=root@YOUR_VPS ./scripts/deploy.sh
```

## Troubleshooting

### "Catalog is empty" on Home

1. Make sure `librefyd` is running and listening on the URL the app is
   pointed at (default `http://127.0.0.1:8080`).
2. Hit `http://127.0.0.1:8080/api/v1/trending` in your browser; you
   should see JSON with `"tracks": [...]`.
3. If the array is empty your local SQLite DB pre-dates the embedded
   seed. Wipe it via the VS Code task **"Librefy: Reset DB"** or:

   ```bash
   find . -maxdepth 4 -name 'librefy.db*' -delete
   ./scripts/run-backend.sh
   ```

4. In the app, tap **Retry** on the empty-catalog card, or restart.

### Pointing the app at a different backend

- **At runtime:** Settings → Backend URL → Apply.
- **At build time:** `flutter run --dart-define=LIBREFY_API=http://your.host:8088`

## Roadmap (not in MVP)

- libtorrent FFI (progressive streaming, fallback to HTTP)
- `LockCachingAudioSource` wiring into `AudioCache` (data plane already done)
- User playlists (device-local, opt-in sync)
- Provider plugin loader

## Contributing

PRs welcome — please read [`docs/LEGAL.md`](docs/LEGAL.md) first.
Any provider PR must surface only verifiably libre content.

## Licensing

Librefy itself is licensed under the **AGPL-3.0**. Every track in the
catalog ships with its own licence metadata; the UI exposes it on the
Now Playing screen.
