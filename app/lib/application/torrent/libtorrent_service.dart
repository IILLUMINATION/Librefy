// Native peer-assisted delivery for Librefy.
//
// LibtorrentService implements [TorrentService] backed by the embedded
// liblibrefy_torrent shared library. It is the "real" implementation;
// HttpOnlyTorrentService is kept as a dev fallback for platforms where
// the .so isn't shipped (web, MVP iOS).
//
// Lifecycle:
//   1. tryInit() opens the native lib and creates a session.
//      If the lib isn't bundled or can't be loaded, returns null and
//      callers must fall back to HttpOnlyTorrentService.
//   2. openMagnet() blocks for metadata (up to [metadataTimeout]), then
//      returns the local HTTP URL where the native streamer serves the
//      first audio file in the torrent.
//   3. dispose() destroys the session and frees all native resources.
//
// Concurrency: every synchronous FFI call that may block (lt_create,
// lt_add_magnet, lt_wait_metadata, lt_stream_url) is dispatched onto a
// helper isolate via [Isolate.run]. This is non-negotiable on Android —
// lt_create alone can take 1–3 s while it spins up DHT, binds sockets
// and warms anacrolix/torrent state, and lt_wait_metadata can hang for
// up to 45 s. Running those on the UI isolate produced reliable ANRs
// ("Window … is not responsive"). The native session itself lives in
// the Go runtime (process-global), so any isolate that calls
// `DynamicLibrary.open` reaches the same shared state.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'libtorrent_bindings.dart';
import 'torrent_service.dart';

const _logTag = 'librefy.torrent';

// Process-global state intentionally kept OUTSIDE the Riverpod scope so
// hot-restart (which throws away ProviderScope and tries to recreate
// everything) doesn't double-init the native session. media_kit + libmpv
// hold onto our HTTP-streamer port through a worker thread, and
// reinitialising while libmpv is still polling produces the dreaded
// "Callback invoked after it has been deleted" crash.
LibtorrentBindings? _globalBindings;
int _globalSessionId = -1;
bool _globalInitFailed = false;

// Serialises tryInit() calls so two parallel "play" taps right after
// cold start can't both kick off `lt_create`.
Completer<void>? _initInFlight;

// ---------------------------------------------------------------------
// Isolate-side workers.
//
// These run inside `Isolate.run`. They cannot capture closures from the
// UI isolate, only their arguments. Each worker reopens the dynamic
// library — that's cheap (dlopen on an already-loaded .so is a no-op
// inside the linker) and gives the isolate its own typed function
// pointers. The underlying native state is process-global.
// ---------------------------------------------------------------------

int _createSessionWorker(String cacheDir) {
  final bindings = LibtorrentBindings.tryOpen();
  if (bindings == null) {
    return -2; // distinct sentinel: dlopen/lookup failure
  }
  final dirPtr = cacheDir.toNativeUtf8();
  try {
    return bindings.ltCreate(dirPtr, 0);
  } finally {
    calloc.free(dirPtr);
  }
}

/// Result envelope so we can carry both the handle/file-count and any
/// native error string back across the isolate boundary in one trip.
class _AddMagnetResult {
  _AddMagnetResult({
    required this.handle,
    required this.fileCount,
    required this.streamUrl,
    required this.error,
  });
  final int handle;
  final int fileCount;
  final String? streamUrl;
  final String? error;
}

/// Stream-URL-only worker used when we already have a handle for this
/// magnet (i.e. we previously opened it inside the same app session and
/// just want a different fileIndex). Skipping add_magnet + wait_metadata
/// matters a lot in practice: with 24-track FLAC albums the wait can be
/// 30–120 s on a cold swarm; re-using the handle drops every track
/// switch after the first to a single FFI call.
class _StreamUrlResult {
  _StreamUrlResult({required this.streamUrl, required this.error});
  final String? streamUrl;
  final String? error;
}

_StreamUrlResult _streamUrlOnlyWorker(
    (int sid, int handle, int fileIndex) args) {
  final bindings = LibtorrentBindings.tryOpen();
  if (bindings == null) {
    return _StreamUrlResult(
        streamUrl: null, error: 'dlopen failed inside worker isolate');
  }
  final (sid, handle, fileIndex) = args;
  final urlPtr = bindings.ltStreamUrl(sid, handle, fileIndex);
  if (urlPtr.address == 0) {
    return _StreamUrlResult(
      streamUrl: null,
      error: 'stream_url: ${bindings.lastError() ?? "null pointer"}',
    );
  }
  final url = urlPtr.toDartString();
  bindings.ltFreeCString(urlPtr);
  return _StreamUrlResult(streamUrl: url, error: null);
}

_AddMagnetResult _addMagnetWorker(
    (int sid, String magnet, int fileIndex, int metadataTimeoutMs) args) {
  final bindings = LibtorrentBindings.tryOpen();
  if (bindings == null) {
    return _AddMagnetResult(
      handle: -1,
      fileCount: -1,
      streamUrl: null,
      error: 'dlopen failed inside worker isolate',
    );
  }
  final (sid, magnet, fileIndex, timeoutMs) = args;

  final magnetPtr = magnet.toNativeUtf8();
  try {
    final handle = bindings.ltAddMagnet(sid, magnetPtr);
    if (handle < 0) {
      return _AddMagnetResult(
        handle: -1,
        fileCount: -1,
        streamUrl: null,
        error: 'lt_add_magnet: ${bindings.lastError() ?? "unknown error"}',
      );
    }

    final fileCount = bindings.ltWaitMetadata(sid, handle, timeoutMs);
    if (fileCount < 0) {
      return _AddMagnetResult(
        handle: handle,
        fileCount: -1,
        streamUrl: null,
        error: 'wait_metadata: ${bindings.lastError() ?? "timeout"}',
      );
    }

    final pickIdx = fileIndex.clamp(0, fileCount - 1);
    final urlPtr = bindings.ltStreamUrl(sid, handle, pickIdx);
    if (urlPtr.address == 0) {
      return _AddMagnetResult(
        handle: handle,
        fileCount: fileCount,
        streamUrl: null,
        error: 'stream_url: ${bindings.lastError() ?? "null pointer"}',
      );
    }
    final url = urlPtr.toDartString();
    bindings.ltFreeCString(urlPtr);

    return _AddMagnetResult(
      handle: handle,
      fileCount: fileCount,
      streamUrl: url,
      error: null,
    );
  } finally {
    calloc.free(magnetPtr);
  }
}

class LibtorrentService implements TorrentService {
  LibtorrentService._(this._bindings, this._sessionId);

  final LibtorrentBindings _bindings;
  final int _sessionId;

  /// All known sessions (one entry per magnet we opened).
  final Map<String, int> _magnetToHandle = {};
  bool _closed = false;

  /// How long to wait for torrent metadata before giving up.
  ///
  /// 45 s was the original value — fine for healthy swarms but way too
  /// short for the realistic Librefy use-case: an operator imports a
  /// FLAC album from a small rutracker thread with 0–2 seeders. Cold
  /// DHT bootstrap on Android easily takes 60–120 s before the first
  /// peer is reachable, and then a few more seconds to actually pull
  /// the .torrent metadata. With the old timeout the user got a
  /// "P2P-only, couldn't open" snackbar even though the magnet was
  /// perfectly valid and would have worked given another minute.
  ///
  /// 180 s is the new ceiling. We still want a hard upper bound so
  /// genuinely dead magnets eventually fail loud instead of hanging
  /// the loading spinner forever.
  static const metadataTimeout = Duration(seconds: 180);

  /// Attempt to load the native library and create a session. Returns
  /// null if the platform doesn't ship it or initialization failed —
  /// callers should fall back to [HttpOnlyTorrentService].
  ///
  /// The native session is cached at top-level scope so a Flutter
  /// hot-restart (which tosses out the Riverpod tree) doesn't try to
  /// create a second session while libmpv is still polling the first.
  static Future<LibtorrentService?> tryInit() async {
    if (_globalInitFailed) return null;
    if (_globalBindings != null && _globalSessionId >= 0) {
      dev.log('reusing existing native session (sid=$_globalSessionId)',
          name: _logTag);
      return LibtorrentService._(_globalBindings!, _globalSessionId);
    }

    // Wait if another caller is already initialising.
    final pending = _initInFlight;
    if (pending != null) {
      await pending.future;
      if (_globalInitFailed) return null;
      if (_globalBindings != null && _globalSessionId >= 0) {
        return LibtorrentService._(_globalBindings!, _globalSessionId);
      }
      return null;
    }

    final completer = Completer<void>();
    _initInFlight = completer;
    try {
      // Open the library on the UI isolate too — we need the typed
      // function pointers locally for openMagnet's lifetime calls
      // (ltRelease, ltStatsJson). Reopening here is cheap; the OS
      // loader returns the same handle.
      final bindings = LibtorrentBindings.tryOpen();
      if (bindings == null) {
        dev.log('native libtorrent unavailable on this platform',
            name: _logTag);
        _globalInitFailed = true;
        return null;
      }

      final dir = await _resolveCacheDir();
      final cacheDir = '$dir/torrent-cache';
      await Directory(cacheDir).create(recursive: true);

      // Critical: lt_create is synchronous and can block 1–3 s on
      // slow devices. MUST run off the UI isolate or it ANRs.
      final sid = await Isolate.run(() => _createSessionWorker(cacheDir));

      if (sid == -2) {
        dev.log('worker isolate failed to open native lib', name: _logTag);
        _globalInitFailed = true;
        return null;
      }
      if (sid < 0) {
        dev.log('ltCreate failed: ${bindings.lastError()}', name: _logTag);
        _globalInitFailed = true;
        return null;
      }
      _globalBindings = bindings;
      _globalSessionId = sid;
      dev.log('libtorrent session up (sid=$sid, cache=$cacheDir)',
          name: _logTag);
      return LibtorrentService._(bindings, sid);
    } finally {
      completer.complete();
      _initInFlight = null;
    }
  }

  @override
  bool get supportsPeerDelivery => !_closed;

  @override
  Future<TorrentSession> openMagnet(String magnet, {int fileIndex = 0}) async {
    if (_closed) {
      throw StateError('LibtorrentService is disposed');
    }
    final sid = _sessionId;

    // Handle reuse: if we already opened this magnet earlier in this
    // app session, the native swarm is still alive (we deliberately do
    // NOT call ltRelease on TorrentSession.dispose — see the comment
    // below). Skip the expensive add-magnet + wait-metadata round-trip
    // and just ask the native streamer for the URL of the requested
    // file. This is what makes track-to-track switches inside one
    // album feel instant instead of hanging on every change while we
    // re-fetch metadata from DHT.
    final existing = _magnetToHandle[magnet];
    if (existing != null) {
      dev.log('openMagnet: cache hit (handle=$existing, file=$fileIndex)',
          name: _logTag);
      final handle = existing;
      final res = await Isolate.run(
        () => _streamUrlOnlyWorker((sid, handle, fileIndex)),
      );
      if (res.error != null || res.streamUrl == null) {
        // Cache may be stale (handle pruned native-side). Drop it and
        // fall through to the slow path so the user still gets playback.
        dev.log('cached handle stale, will re-add: ${res.error}',
            name: _logTag);
        _magnetToHandle.remove(magnet);
      } else {
        return TorrentSession(
          localUri: Uri.parse(res.streamUrl!),
          dispose: _noopSessionDispose,
          stats: _statsStream(handle),
        );
      }
    }

    dev.log('openMagnet: cold path (file=$fileIndex)', name: _logTag);
    final timeoutMs = metadataTimeout.inMilliseconds;
    // Run the entire add → wait-metadata → stream-url chain in a
    // worker isolate. wait_metadata alone can block up to 180 s now;
    // doing it on the UI isolate is what produced the ANRs on Android.
    final result = await Isolate.run(
      () => _addMagnetWorker((sid, magnet, fileIndex, timeoutMs)),
    );

    if (result.error != null) {
      // Don't ltRelease here either — see the comment on
      // _noopSessionDispose. The handle (if we got one) stays
      // registered in the native session and may be retried.
      throw Exception(result.error);
    }
    final handle = result.handle;
    final fileCount = result.fileCount;
    final url = result.streamUrl!;
    _magnetToHandle[magnet] = handle;
    dev.log(
      'magnet opened: handle=$handle, files=$fileCount, url=$url',
      name: _logTag,
    );

    return TorrentSession(
      localUri: Uri.parse(url),
      // See _noopSessionDispose: we intentionally keep the native
      // handle alive past the session that opened it.
      dispose: _noopSessionDispose,
      stats: _statsStream(handle),
    );
  }

  /// We intentionally do NOT call ltRelease when a TorrentSession is
  /// disposed. Two reasons:
  ///
  ///  1. A single album typically maps to one magnet with many tracks.
  ///     Releasing the handle when the user skips to the next track
  ///     means every skip re-pays the DHT + wait-metadata cost
  ///     (30–120 s on cold swarms). Reuse drops that to a single FFI
  ///     call.
  ///
  ///  2. media_kit's libmpv worker thread keeps reading from the
  ///     loopback HTTP streamer for a brief grace period after the
  ///     player switches sources. Yanking the handle synchronously
  ///     from underneath it is exactly the race that produced the
  ///     "Callback invoked after it has been deleted" crash on
  ///     Android.
  ///
  /// Net effect: handles accumulate inside the native session for the
  /// app's process lifetime, and the OS reclaims them on process exit.
  /// Memory cost: ~tens of KB per active swarm, well under the budget.
  /// A future iteration can add LRU eviction once we ship the
  /// "currently downloading" management UI.
  static Future<void> _noopSessionDispose() async {}

  /// Poll the native stats endpoint periodically and surface as a stream.
  /// Each poll is a quick FFI call (no blocking I/O) — safe on the UI
  /// isolate.
  ///
  /// The stream ends when [_closed] is set (service-level dispose) or
  /// when the listener cancels their StreamSubscription. We no longer
  /// gate on _magnetToHandle membership: since track switches reuse
  /// the same handle, the polling loop has to outlive any individual
  /// session.
  Stream<TorrentStats> _statsStream(int handle) async* {
    const buf = 1024;
    while (!_closed) {
      final out = calloc<ffi.Char>(buf);
      try {
        final n = _bindings.ltStatsJson(_sessionId, handle, out, buf);
        if (n > 0) {
          final raw = out.cast<Utf8>().toDartString();
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            yield TorrentStats(
              peers: (map['peers'] as num?)?.toInt() ?? 0,
              downloadRateBps: 0, // anacrolix Stats doesn't expose rate directly
              progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
            );
          } catch (_) {
            // bad JSON, skip frame
          }
        }
      } finally {
        calloc.free(out);
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
  }

  Future<void> dispose() async {
    // NOTE: we intentionally do NOT call ltDestroy here. The native
    // session is owned by top-level state that survives Riverpod
    // teardown — destroying it during hot-restart is precisely what
    // produces the libmpv "Callback after deleted" crash. The OS
    // reclaims the session when the process exits.
    if (_closed) return;
    _closed = true;
    dev.log('LibtorrentService disposed (native session kept alive)',
        name: _logTag);
  }

  static Future<String> _resolveCacheDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }
}
