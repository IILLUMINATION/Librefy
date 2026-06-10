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

// Hide media_kit's `Track` to avoid clashing with domain.Track.
import 'package:media_kit/media_kit.dart' hide Track;

import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../torrent/source_resolver.dart';

const _logTag = 'librefy.audio';

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
  });

  final List<Track> queue;
  final int currentIndex;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final bool usingP2P;

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
  }) =>
      PlaybackSnapshot(
        queue: queue ?? this.queue,
        currentIndex: currentIndex ?? this.currentIndex,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        duration: duration ?? this.duration,
        usingP2P: usingP2P ?? this.usingP2P,
      );

  static const empty = PlaybackSnapshot(
    queue: <Track>[],
    currentIndex: -1,
    playing: false,
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
    usingP2P: false,
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

class AudioPlayerService {
  AudioPlayerService({
    required CatalogRepository repository,
    required SourceResolver resolver,
    Player? player,
  })  : _repo = repository,
        _resolver = resolver,
        _player = player ?? Player() {
    _wirePlayerEvents();
  }

  final CatalogRepository _repo;
  final SourceResolver _resolver;
  final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _snapshotCtrl = StreamController<PlaybackSnapshot>.broadcast();
  final _errorCtrl = StreamController<PlaybackError>.broadcast();
  PlaybackSnapshot _snap = PlaybackSnapshot.empty;

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
    if (_snap.currentIndex + 1 >= _snap.queue.length) return;
    _emit(_snap.copyWith(currentIndex: _snap.currentIndex + 1));
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

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _snapshotCtrl.close();
    await _errorCtrl.close();
  }

  Future<void> _loadAndPlayCurrent() async {
    final track = _snap.current;
    if (track == null) return;

    dev.log('▶ loadAndPlay id=${track.id} title="${track.title}"', name: _logTag);

    try {
      // Step 1 — ask the backend where to fetch the audio.
      final info = await _repo.resolveStream(track.id);
      dev.log(
        '  resolveStream → httpUrl=${info.httpUrl ?? "-"} '
        'magnet=${info.magnet?.isNotEmpty == true ? "yes" : "no"} '
        'mime=${info.mimeType}',
        name: _logTag,
      );

      // Step 2 — pick best transport (P2P or HTTP).
      final resolved = await _resolver.resolve(info);
      dev.log(
        '  source resolved → ${resolved.uri} (p2p=${resolved.usingP2P})',
        name: _logTag,
      );

      // Step 3 — hand the URI to media_kit. `play: true` starts playback
      // immediately. Older media_kit defaulted to true but we set it
      // explicitly so behaviour cannot regress on upgrades.
      await _player.open(Media(resolved.uri.toString()), play: true);
      _emit(_snap.copyWith(usingP2P: resolved.usingP2P));

      // Step 4 — defensive: some builds (especially fresh installs) need
      // an explicit play() call right after open() to actually begin.
      await _player.play();

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
      if (done) unawaited(next());
    }));
    // media_kit emits an `error` stream of strings whenever libmpv reports
    // something. We forward those to the UI / log so it's obvious what
    // failed (bad URL, codec, network, …).
    _subs.add(_player.stream.error.listen((err) {
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
}
