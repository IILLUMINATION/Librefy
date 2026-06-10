# Peer-assisted streaming in Librefy

Librefy's headline feature: tracks linked by a magnet URI play directly
from the BitTorrent swarm, **on the user's device**, with no fan-out
through the Librefy backend. The backend stores metadata; bytes flow
peer ↔ peer.

This document explains how the bridge is built and how to add to it.

## Pipeline at a glance

```
[ user taps Play ]
       │
       ▼
AudioPlayerService            (Dart)
       │ resolveStream
       ▼
CatalogRepository ── HTTP ──► librefyd  (Go, VPS)
       │                       returns {magnet, httpUrl, …}
       ▼
SourceResolver                 (Dart)
       │ "has magnet AND P2P available?"
       ▼ yes
LibtorrentService              (Dart FFI)
       │ ltAddMagnet / ltWaitMetadata / ltStreamUrl
       ▼
liblibrefy_torrent.so          (Go c-shared, embedded into the app)
   ├── anacrolix/torrent       Client + DHT + peer connections
   └── HTTP streamer @ 127.0.0.1:<port>/<infoHash>/<fileIdx>
       │
       ▼
media_kit / mpv                ← reads HTTP with Range like a CDN
```

## Components

### `native/librefy-torrent/`

Pure Go module compiled as a c-shared library
(`liblibrefy_torrent.so` / `.dylib` / `.dll`). Exposes a tiny C API
through cgo `//export`:

| C symbol | Purpose |
|---|---|
| `lt_create` | open a `torrent.Client` with a cache directory |
| `lt_destroy` | close client, free all native state |
| `lt_add_magnet` | register a magnet URI, returns an opaque handle |
| `lt_wait_metadata` | block (up to N ms) until `<info>` is fetched |
| `lt_stream_url` | local HTTP URL for file [N] of the torrent |
| `lt_stats_json` | snapshot of peers / progress / sizes |
| `lt_release` | drop a torrent (keeps disk cache) |
| `lt_last_error` | latest error string from any thread |
| `lt_free_cstring` | free any C string returned to Dart |

The HTTP streamer wraps anacrolix's `Torrent.Files()[i].NewReader()` in
an `io.ReadSeeker` and lets the Go stdlib's `http.ServeContent` handle
Range requests properly. media_kit consumes the URL exactly like it
would a Cloudflare-hosted MP3.

### `app/lib/application/torrent/`

- `torrent_service.dart` — interface (`TorrentService`) + types.
- `http_only_torrent_service.dart` — safe stub (`supportsPeerDelivery: false`).
- `libtorrent_bindings.dart` — hand-written FFI bindings (8 lookups).
- `libtorrent_service.dart` — the real implementation. Falls back to the
  stub when `LibtorrentBindings.tryOpen()` fails (the .so isn't shipped
  in this build / unsupported platform).
- `source_resolver.dart` — chooses P2P vs HTTP per request.

The Riverpod provider (`torrentServiceProvider`) is async because we
have to call `LibtorrentService.tryInit()` once at startup. The chained
`_activeTorrentServiceProvider` provides synchronous access for
`SourceResolver`, falling back to the stub while init is in-flight.

## Building the native library

### Linux desktop

```bash
./scripts/build-native.sh
```

Produces `app/linux/libs/liblibrefy_torrent.so` (~23 MiB stripped).
The Flutter Linux build (CMake) copies it into `bundle/lib/`; the runner's
RPATH `$ORIGIN/lib` picks it up at start, same mechanism as for libmpv.

### Android

```bash
./scripts/build-native-android.sh                       # all three ABIs
ABIS="arm64-v8a" ./scripts/build-native-android.sh      # one ABI only
```

Requires `ANDROID_NDK_HOME` (or NDK auto-detected under
`~/Android/Sdk/ndk/<latest>`). Outputs land in
`app/android/app/src/main/jniLibs/<abi>/` and Gradle packs them into
the APK without extra configuration.

### Important build flags

We pass `-ldflags="-s -w -checklinkname=0"`. The last flag is **required**
because `wlynxg/anet` (transitive dependency of anacrolix/torrent for
Android-friendly interface enumeration) uses `//go:linkname` against
unexported net package symbols. Go 1.23+ blocks this by default.

## Runtime behaviour

### First-run dialog

The first time the app starts on a build that has the native library
loaded, the user sees an explainer + opt-in switch ("Enable peer
delivery"). The choice is persisted in `SharedPreferences` and respected
from then on; flipping it in Settings is wired the same way.

When disabled, `_activeTorrentServiceProvider` returns the HTTP-only stub
even if the native lib is loaded — magnet-only tracks then surface the
"track has no playable HTTP source" snackbar.

### Cache

Sessions store pieces under `<applicationSupportDirectory>/torrent-cache`
(Linux: `~/.local/share/librefy/torrent-cache`; Android: app-private
storage). Anacrolix's default piece store is filesystem-backed; restarting
the app and re-adding the same magnet reuses already-downloaded pieces
without re-fetching them.

### Peer indicator

The Now Playing screen shows a `P2P` chip in the AppBar whenever the
current source was resolved through `LibtorrentService`. (Future
improvement: live peer count + rate from `lt_stats_json`.)

## Legal & ethical

- Only magnets that operators explicitly enter in the admin panel are
  ever opened — the official build does not accept arbitrary user input.
- The admin panel forces a `license` field on every track. Validate
  upstream; if it's not redistributable, do not add it.
- The native library seeds back to the swarm by default while a torrent
  is in cache. This is *good citizenship* in BitTorrent ecosystems and
  the right behaviour for libre content.
- Users can disable peer delivery entirely from Settings.

## Known limitations (MVP)

1. iOS — not built. Apple makes pure-Go shared libraries painful;
   we'll revisit with libtorrent-rasterbar later.
2. Stats expose peer count but not download rate (anacrolix `Stats` API
   doesn't surface it). Add a moving-average sampler later.
3. No cache-size enforcement on the client side yet. Cache grows
   unbounded until disk fills. Need an LRU pass.
4. Background P2P on Android is best-effort: Doze may suspend the
   client when the screen goes off. Music keeps playing while it's
   active; when restored, the swarm re-establishes.
