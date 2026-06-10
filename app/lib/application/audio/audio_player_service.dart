// AudioPlayerService — thin wrapper around media_kit's Player.
//
// Why media_kit (and not just_audio):
//   - media_kit ships its own libmpv binaries through media_kit_libs_*,
//     so a fresh user does NOT have to fight platform plugins.
//   - Same API across Android, iOS, Linux, Windows, macOS.
//
// Responsibilities of this class:
//   - Maintain the playback queue and current index.
//   - Resolve each track's StreamInfo just-in-time and feed the right
//     URI to the player (P2P-or-HTTP via SourceResolver).
//   - Surface a unified PlaybackSnapshot for the UI.
//   - Surface playback / resolution errors via [errors] so the UI can
//     show a snackbar and the user can paste the log to the issue tracker.
//   - Record anonymous play events through the repository.
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
// Hide media_kit's `Track` to avoid clashing with domain.Track.
import 'package:media_kit/media_kit.dart' hide Track;

import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../torrent/source_resolver.dart';
import '../torrent/torrent_service.dart';

const _logTag = 'librefy.audio';

/// What the player does when the current track ends.
///
/// Named PlayerRepeatMode (not just PlayerRepeatMode) to avoid colliding with
/// Flutter material's animation PlayerRepeatMode enum.
enum PlayerRepeatMode {
  off,  // advance to next; stop after the last track
  one,  // replay current track forever
  all,  // wrap around to track 0 after the last
}

/// Snapshot of player state, kept transport-agnostic so the UI does
/// not need to import media_kit.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.playing,
    required this.position,
    required this.bufferedPosition,
    required this.duration,
    required this.usingP2P,
    required this.p2pProgress,
    required this.p2pPeers,
    required this.repeatMode,
    required this.shuffle,
  });

  final List<Track> queue;
  final int currentIndex;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final bool usingP2P;
  final double p2pProgress;
  final int p2pPeers;
  final PlayerRepeatMode repeatMode;
  final bool shuffle;

  Track? get current =>
      (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;

  PlaybackSnapshot copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? playing,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    bool? usingP2P,
    double? p2pProgress,
    int? p2pPeers,
    PlayerRepeatMode? repeatMode,
    bool? shuffle,
  }) =>
      PlaybackSnapshot(
        queue: queue ?? this.queue,
        currentIndex: currentIndex ?? this.currentIndex,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        duration: duration ?? this.duration,
        usingP2P: usingP2P ?? this.usingP2P,
        p2pProgress: p2pProgress ?? this.p2pProgress,
        p2pPeers: p2pPeers ?? this.p2pPeers,
        repeatMode: repeatMode ?? this.repeatMode,
        shuffle: shuffle ?? this.shuffle,
      );

  static const empty = PlaybackSnapshot(
    queue: <Track>[],
    currentIndex: -1,
    playing: false,
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
    usingP2P: false,
    p2pProgress: 0,
    p2pPeers: 0,
    repeatMode: PlayerRepeatMode.off,
    shuffle: false,
  );
}

/// A single error event surfaced from the audio pipeline.
class PlaybackError {
  PlaybackError(this.message, {this.cause, this.trackId})
      : at = DateTime.now();
  final String message;
  final Object? cause;
  final String? trackId;
  final DateTime at;

  @override
  String toString() =>
      '[$at] ${trackId != null ? "($trackId) " : ""}$message'
      '${cause != null ? "\n  cause: $cause" : ""}';
}

/// Process-global Player. Lives outside the Riverpod scope on purpose:
/// when Flutter performs a hot-restart it throws away every ProviderScope
/// and re-runs main(), but libmpv's worker thread is still mid-callback
/// into a Dart trampoline that the VM is about to delete. Tearing down
/// the Player in that moment produces the dreaded crash:
///
///   error: Callback invoked after it has been deleted.
///   F/libc: Fatal signal 6 (SIGABRT) in tid (mpv/mpv core)
///
/// By keeping the same Player instance across hot-restarts (mirroring
/// what we already do for the native libtorrent session) the libmpv
/// worker keeps talking to the same callback table for the lifetime of
/// the process, and the crash disappears.
///
/// Tradeoff: we never call _player.dispose() — the OS reclaims it when
/// the process exits. In practice the Player object is small (a few
/// MiB of internal buffers plus libmpv state) and Riverpod's lifetime
/// isn't a tight enough scope to justify the crash risk.
Player? _globalPlayer;

/// Default configuration used when we create the singleton on first use.
/// Tunings rationale:
///   * `logLevel`: in debug builds keep warn so codec / url issues are
///     visible. In release lower to error to avoid burning main-thread
///     time on FFI log callbacks.
///   * `bufferSize`: 16 MiB — libmpv internally uses this for the demux
///     queue. 16 MiB is plenty for audio (a 320 kbps stream = ~40 KiB/s;
///     16 MiB ≈ 7 minutes of buffer). The previous 64 MiB was sized for
///     video and caused noticeable cold-start allocation cost on Android.
PlayerConfiguration _playerConfig() => PlayerConfiguration(
      title: 'Librefy',
      logLevel: kDebugMode ? MPVLogLevel.warn : MPVLogLevel.error,
      bufferSize: 16 * 1024 * 1024,
    );

Player _ensureGlobalPlayer() {
  final existing = _globalPlayer;
  if (existing != null) return existing;
  final p = Player(configuration: _playerConfig());
  _globalPlayer = p;
  return p;
}

class AudioPlayerService {
  AudioPlayerService({
    required CatalogRepository repository,
    required SourceResolver resolver,
    Player? player,
  })  : _repo = repository,
        _resolver = resolver,
        _player = player ?? _ensureGlobalPlayer() {
    _wirePlayerEvents();
    _configureMpv();
  }

  /// Apply libmpv runtime tunings that aren't exposed through
  /// [PlayerConfiguration]. Best-effort: if any property fails (e.g. the
  /// web backend doesn't expose mpv) we just log and move on.
  ///
  /// Rationale:
  ///   - `ytdl=no` disables the youtube-dl/yt-dlp hook. libmpv runs it on
  ///     every URL by default and prints noisy "Subprocess failed: init"
  ///     errors when the binary isn't installed. Librefy never plays
  ///     YouTube URLs, so this is pure noise + a small latency hit.
  ///   - `network-timeout=30` raises libmpv's HTTP read timeout from the
  ///     default 5s to 30s. The loopback torrent streamer needs a few
  ///     seconds to fetch the first pieces from peers before bytes start
  ///     flowing; the old default produced "Время ожидания соединения
  ///     истекло" / "Failed to open" on slow swarms.
  ///   - `cache=yes` + `cache-secs=10` keeps a small forward buffer so a
  ///     temporary peer stall doesn't underrun the player.
  void _configureMpv() {
    final platform = _player.platform;
    if (platform == null) return;
    // ignore: avoid_dynamic_calls
    final dyn = platform as dynamic;
    Future<void> trySet(String key, String value) async {
      try {
        await dyn.setProperty(key, value);
      } catch (e) {
        dev.log('  mpv setProperty $key=$value ignored: $e', name: _logTag);
      }
    }

    unawaited(() async {
      await trySet('ytdl', 'no');
      await trySet('network-timeout', '30');
      await trySet('cache', 'yes');
      await trySet('cache-secs', '10');
      await trySet('demuxer-readahead-secs', '10');
    }());
  }

  final CatalogRepository _repo;
  final SourceResolver _resolver;
  final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _snapshotCtrl = StreamController<PlaybackSnapshot>.broadcast();
  final _errorCtrl = StreamController<PlaybackError>.broadcast();
  PlaybackSnapshot _snap = PlaybackSnapshot.empty;

  // Currently-attached torrent session. Disposed when we switch tracks
  // (with a small delay so libmpv has time to release its FD on the
  // local HTTP server — otherwise we crash with "Callback invoked after
  // it has been deleted" because libmpv's network thread still calls
  // back into the dying handle).
  TorrentSession? _activeSession;
  StreamSubscription<TorrentStats>? _activeStatsSub;

  // Serialise loads. We must not start opening track N+1 while N is
  // still spinning up; media_kit's libmpv backend keeps file-handles
  // open and can re-enter our FFI after we tear it down.
  Future<void> _loadOp = Future.value();
  int _generation = 0;

  Stream<PlaybackSnapshot> get snapshots => _snapshotCtrl.stream;
  Stream<PlaybackError> get errors => _errorCtrl.stream;
  PlaybackSnapshot get current => _snap;

  Future<void> playTrack(Track track) => playQueue([track], startIndex: 0);

  /// Replace the queue and start playback at [startIndex].
  Future<void> playQueue(List<Track> queue, {int startIndex = 0}) async {
    _emit(_snap.copyWith(queue: queue, currentIndex: startIndex));
    await _loadAndPlayCurrent();
  }

  Future<void> next() async {
    final nextIndex = _pickNextIndex(auto: false);
    if (nextIndex == null) return;
    _emit(_snap.copyWith(currentIndex: nextIndex));
    await _loadAndPlayCurrent();
  }

  Future<void> previous() async {
    // Spotify behaviour: restart current track if past 3s, else skip back.
    if (_snap.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_snap.currentIndex <= 0) {
      await _player.seek(Duration.zero);
      return;
    }
    _emit(_snap.copyWith(currentIndex: _snap.currentIndex - 1));
    await _loadAndPlayCurrent();
  }

  /// Cycle: off → all → one → off
  void cycleRepeatMode() {
    final next = switch (_snap.repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    _emit(_snap.copyWith(repeatMode: next));
  }

  void toggleShuffle() {
    _emit(_snap.copyWith(shuffle: !_snap.shuffle));
  }

  /// Returns the queue index to play next, or null if the queue is at
  /// its end and repeatMode forbids wrapping.
  ///
  /// [auto] is true when this was invoked from the player's "completed"
  /// event (so repeat.one applies); false when triggered by the user
  /// hitting the next button (skip past current track regardless).
  int? _pickNextIndex({required bool auto}) {
    if (_snap.queue.isEmpty) return null;

    if (auto && _snap.repeatMode == PlayerRepeatMode.one) {
      return _snap.currentIndex;
    }

    if (_snap.shuffle) {
      if (_snap.queue.length == 1) return 0;
      // Pick any other index uniformly at random.
      final rnd = (DateTime.now().microsecondsSinceEpoch ^ hashCode).abs();
      var pick = rnd % _snap.queue.length;
      if (pick == _snap.currentIndex) {
        pick = (pick + 1) % _snap.queue.length;
      }
      return pick;
    }

    final candidate = _snap.currentIndex + 1;
    if (candidate < _snap.queue.length) return candidate;
    if (_snap.repeatMode == PlayerRepeatMode.all) return 0;
    return null;
  }

  Future<void> togglePlay() async {
    try {
      if (_player.state.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e, st) {
      _reportError('togglePlay failed', cause: e, stack: st);
    }
  }

  Future<void> seek(Duration to) async {
    try {
      await _player.seek(to);
    } catch (e, st) {
      _reportError('seek failed', cause: e, stack: st);
    }
  }

  /// Resolves the same URI media_kit would play for [trackId] but
  /// without touching the player state. Used by the download flow so a
  /// "save to device" tap on a magnet-backed track downloads from the
  /// loopback torrent stream we're already maintaining.
  ///
  /// Returns the resolved URI. The caller does NOT own the
  /// [TorrentSession] returned alongside — it lives as long as the
  /// underlying torrent is in cache.
  Future<({Uri uri, bool usingP2P})> resolveForDownload(String trackId) async {
    final info = await _repo.resolveStream(trackId);
    final resolved = await _resolver.resolve(info);
    return (uri: resolved.uri, usingP2P: resolved.usingP2P);
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    try {
      await _activeStatsSub?.cancel();
    } catch (_) {}
    _activeStatsSub = null;
    final old = _activeSession;
    _activeSession = null;
    if (old != null) {
      // Best-effort; never throw out of dispose or hot-restart crashes.
      unawaited(Future(() async {
        try {
          await old.dispose();
        } catch (_) {}
      }));
    }
    // Stop playback so libmpv's worker thread releases its sources, but
    // do NOT call _player.dispose(): the player is the process-global
    // singleton (see _globalPlayer at top of file). Disposing it during
    // a Riverpod teardown / hot-restart while libmpv is still mid-callback
    // is exactly what produced "Callback invoked after it has been
    // deleted" SIGABRTs in past iterations. The next AudioPlayerService
    // will reuse the same Player.
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _snapshotCtrl.close();
    } catch (_) {}
    try {
      await _errorCtrl.close();
    } catch (_) {}
  }

  /// Queues the load. Multiple rapid taps on next/previous collapse into
  /// a single serialised chain — we never open() while a previous open()
  /// is still resolving.
  Future<void> _loadAndPlayCurrent() {
    final gen = ++_generation;
    _loadOp = _loadOp.then((_) => _runLoad(gen)).catchError((Object e, StackTrace st) {
      _reportError('load chain crashed', cause: e, stack: st);
    });
    return _loadOp;
  }

  Future<void> _runLoad(int gen) async {
    // If the user pressed next/prev again while we were waiting, skip
    // this stale generation entirely.
    if (gen != _generation) return;

    final track = _snap.current;
    if (track == null) return;

    dev.log('▶ loadAndPlay gen=$gen id=${track.id} title="${track.title}"',
        name: _logTag);

    // Stop the currently-playing source BEFORE we mutate any state so
    // libmpv's network thread tears down its connection to the old URL
    // before we close the torrent session that was serving it.
    try {
      await _player.stop();
    } catch (e) {
      dev.log('  player.stop ignored: $e', name: _logTag);
    }

    try {
      final info = await _repo.resolveStream(track.id);
      if (gen != _generation) return;
      dev.log(
        '  resolveStream → httpUrl=${info.httpUrl ?? "-"} '
        'magnet=${info.magnet?.isNotEmpty == true ? "yes" : "no"} '
        'mime=${info.mimeType}',
        name: _logTag,
      );

      final resolved = await _resolver.resolve(info);
      if (gen != _generation) {
        // We got pre-empted — release the session we just opened (if any)
        // so it doesn't leak.
        if (resolved.session != null) {
          await resolved.session!.dispose();
        }
        return;
      }
      dev.log(
        '  source resolved → ${resolved.uri} (p2p=${resolved.usingP2P})',
        name: _logTag,
      );

      // Swap sessions: keep the previous one alive while libmpv finishes
      // reading any in-flight bytes, then dispose it after a short grace
      // period. This is the main fix for the "Callback invoked after it
      // has been deleted" crash: libmpv's HTTP worker thread can still
      // be reading from the old local server when we'd otherwise tear it
      // down synchronously, which yanks a buffer out from under it.
      final previousSession = _activeSession;
      final previousStatsSub = _activeStatsSub;
      _activeSession = resolved.session;
      _activeStatsSub = null;

      // Reset peer/progress counters; subscribe to the new session if any.
      _emit(_snap.copyWith(
        usingP2P: resolved.usingP2P,
        p2pPeers: 0,
        p2pProgress: 0,
      ));
      if (resolved.session != null) {
        _activeStatsSub = resolved.session!.stats.listen((s) {
          if (gen != _generation) return;
          _emit(_snap.copyWith(
            p2pPeers: s.peers,
            p2pProgress: s.progress,
          ));
        });
      }

      // If the resolved URI points at our loopback torrent streamer, the
      // server is up the instant lt_stream_url returns BUT the first
      // pieces may still be downloading. libmpv's HTTP reader will time
      // out and bail with "Failed to open" if it connects before the
      // streamer has bytes to serve. Probe the URL until it returns a
      // 2xx/206 (or until we give up after ~10s) before handing it to
      // libmpv. Non-loopback HTTP sources skip the probe — the real
      // backend is expected to respond fast.
      if (_isLoopbackHttp(resolved.uri)) {
        final ok = await _waitForStream(resolved.uri,
            attempts: 20, perAttemptTimeout: const Duration(seconds: 1));
        if (gen != _generation) return;
        if (!ok) {
          dev.log('  stream readiness probe failed, opening anyway',
              name: _logTag);
        }
      }

      await _player.open(Media(resolved.uri.toString()), play: true);

      if (previousStatsSub != null) {
        await previousStatsSub.cancel();
      }
      if (previousSession != null) {
        Future<void>.delayed(const Duration(seconds: 3), () async {
          try {
            await previousSession.dispose();
          } catch (e) {
            dev.log('  previousSession.dispose: $e', name: _logTag);
          }
        });
      }

      unawaited(_repo.recordPlay(track.id));
    } catch (e, st) {
      _reportError(
        'Could not start playback',
        cause: e,
        stack: st,
        trackId: track.id,
      );
    }
  }

  void _wirePlayerEvents() {
    _subs.add(_player.stream.playing.listen((p) {
      dev.log('player.playing → $p', name: _logTag);
      _emit(_snap.copyWith(playing: p));
    }));
    _subs.add(_player.stream.position.listen((p) {
      _emit(_snap.copyWith(position: p));
    }));
    _subs.add(_player.stream.duration.listen((d) {
      dev.log('player.duration → ${d.inMilliseconds}ms', name: _logTag);
      _emit(_snap.copyWith(duration: d));
    }));
    _subs.add(_player.stream.buffer.listen((b) {
      _emit(_snap.copyWith(bufferedPosition: b));
    }));
    _subs.add(_player.stream.completed.listen((done) {
      dev.log('player.completed → $done', name: _logTag);
      if (!done) return;
      final auto = _pickNextIndex(auto: true);
      if (auto == null) {
        // Queue end with repeat off → stop here.
        _emit(_snap.copyWith(playing: false));
        return;
      }
      _emit(_snap.copyWith(currentIndex: auto));
      unawaited(_loadAndPlayCurrent());
    }));
    // media_kit emits an `error` stream of strings whenever libmpv reports
    // something. We forward those to the UI / log so it's obvious what
    // failed (bad URL, codec, network, …).
    //
    // Exception: libmpv occasionally complains "property not found" for
    // keys media_kit tries to set on every Player init (subs-fallback,
    // osc, …). On Android in particular those keys don't exist in the
    // audio-only build of libmpv that media_kit ships. The errors are
    // cosmetic — libmpv just ignores the unknown property — but they
    // would otherwise bubble up to the user as a scary snackbar on every
    // app start. Whitelist that substring to dev.log only.
    _subs.add(_player.stream.error.listen((err) {
      if (err.contains('property not found')) {
        dev.log('mpv (ignored): $err', name: _logTag);
        return;
      }
      _reportError('libmpv: $err');
    }));
    _subs.add(_player.stream.log.listen((entry) {
      dev.log('mpv[${entry.level}] ${entry.prefix}: ${entry.text}',
          name: _logTag);
    }));
  }

  void _reportError(String message,
      {Object? cause, StackTrace? stack, String? trackId}) {
    dev.log('✗ $message', name: _logTag, error: cause, stackTrace: stack);
    if (!_errorCtrl.isClosed) {
      _errorCtrl.add(PlaybackError(message, cause: cause, trackId: trackId));
    }
  }

  void _emit(PlaybackSnapshot s) {
    _snap = s;
    if (!_snapshotCtrl.isClosed) _snapshotCtrl.add(s);
  }

  static bool _isLoopbackHttp(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host;
    return host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '::1' ||
        host.startsWith('127.');
  }

  /// Issues a small Range GET (or HEAD as fallback) to [uri] up to
  /// [attempts] times until the server responds successfully. Returns
  /// true on the first 2xx/206 response.
  ///
  /// We deliberately use a fresh HttpClient per call: the torrent
  /// streamer is process-local, requests are cheap, and we want zero
  /// pooling so a stale connection from a previous track can't be
  /// reused (libmpv just disposed of one).
  Future<bool> _waitForStream(Uri uri,
      {required int attempts,
      Duration perAttemptTimeout = const Duration(seconds: 1)}) async {
    final client = HttpClient()
      ..connectionTimeout = perAttemptTimeout
      ..idleTimeout = const Duration(seconds: 2);
    try {
      for (var i = 0; i < attempts; i++) {
        try {
          final req = await client
              .getUrl(uri)
              .timeout(perAttemptTimeout);
          // Ask for a single byte so the streamer doesn't have to
          // queue large amounts of data to satisfy the probe.
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
          final resp = await req.close().timeout(perAttemptTimeout);
          // Drain & close immediately — we only care about the status.
          await resp.drain<void>().timeout(perAttemptTimeout);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            dev.log('  stream ready after ${i + 1} probe(s) '
                '(status=${resp.statusCode})', name: _logTag);
            return true;
          }
          dev.log('  probe #${i + 1} status=${resp.statusCode}', name: _logTag);
        } on TimeoutException {
          // Streamer not answering yet; sleep briefly and retry.
        } catch (e) {
          dev.log('  probe #${i + 1} error: $e', name: _logTag);
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
