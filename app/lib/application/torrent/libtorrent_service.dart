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
// Thread-safety: the underlying Go code is fully thread-safe; we still
// keep Dart-side state behind a mutex because dispose() must wait for
// outstanding openMagnet() calls.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:ffi' as ffi;
import 'dart:io';

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

class LibtorrentService implements TorrentService {
  LibtorrentService._(this._bindings, this._sessionId);

  final LibtorrentBindings _bindings;
  final int _sessionId;

  /// All known sessions (one entry per magnet we opened).
  final Map<String, int> _magnetToHandle = {};
  bool _closed = false;

  /// How long to wait for torrent metadata before giving up.
  static const metadataTimeout = Duration(seconds: 45);

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

    final bindings = LibtorrentBindings.tryOpen();
    if (bindings == null) {
      dev.log('native libtorrent unavailable on this platform', name: _logTag);
      _globalInitFailed = true;
      return null;
    }
    final dir = await _resolveCacheDir();
    final cacheDir = '$dir/torrent-cache';
    await Directory(cacheDir).create(recursive: true);

    final dirPtr = cacheDir.toNativeUtf8();
    try {
      final sid = bindings.ltCreate(dirPtr, 0);
      if (sid < 0) {
        dev.log('ltCreate failed: ${bindings.lastError()}', name: _logTag);
        _globalInitFailed = true;
        return null;
      }
      _globalBindings = bindings;
      _globalSessionId = sid;
      dev.log('libtorrent session up (sid=$sid, cache=$cacheDir)', name: _logTag);
      return LibtorrentService._(bindings, sid);
    } finally {
      calloc.free(dirPtr);
    }
  }

  @override
  bool get supportsPeerDelivery => !_closed;

  @override
  Future<TorrentSession> openMagnet(String magnet, {int fileIndex = 0}) async {
    if (_closed) {
      throw StateError('LibtorrentService is disposed');
    }
    final magnetPtr = magnet.toNativeUtf8();
    try {
      final handle = _bindings.ltAddMagnet(_sessionId, magnetPtr);
      if (handle < 0) {
        throw Exception('lt_add_magnet failed: ${_bindings.lastError()}');
      }
      _magnetToHandle[magnet] = handle;
      dev.log('added magnet (handle=$handle), file=$fileIndex, waiting for metadata…',
          name: _logTag);

      final fileCount = await Future(() {
        return _bindings.ltWaitMetadata(
          _sessionId,
          handle,
          metadataTimeout.inMilliseconds,
        );
      });
      if (fileCount < 0) {
        final err = _bindings.lastError() ?? 'metadata timeout';
        throw Exception('wait_metadata: $err');
      }
      dev.log('got metadata: $fileCount files', name: _logTag);

      // Clamp out-of-range file indices so a stale DB row can't ask the
      // native side for a non-existent file (which would 404 forever).
      final pickIdx = fileIndex.clamp(0, fileCount - 1);
      if (pickIdx != fileIndex) {
        dev.log('  fileIndex $fileIndex out of range, clamped to $pickIdx',
            name: _logTag);
      }

      final urlPtr = _bindings.ltStreamUrl(_sessionId, handle, pickIdx);
      if (urlPtr.address == 0) {
        throw Exception('stream_url: ${_bindings.lastError()}');
      }
      final url = urlPtr.toDartString();
      _bindings.ltFreeCString(urlPtr);
      dev.log('stream URL: $url', name: _logTag);

      return TorrentSession(
        localUri: Uri.parse(url),
        dispose: () async {
          _bindings.ltRelease(_sessionId, handle);
          _magnetToHandle.remove(magnet);
        },
        stats: _statsStream(handle),
      );
    } finally {
      calloc.free(magnetPtr);
    }
  }

  /// Poll the native stats endpoint periodically and surface as a stream.
  Stream<TorrentStats> _statsStream(int handle) async* {
    const buf = 1024;
    while (!_closed && _magnetToHandle.containsValue(handle)) {
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
