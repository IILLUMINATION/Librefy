// AudioPlayerService — thin wrapper around media_kit's Player.
//
// Why media_kit (and not just_audio):
//   - media_kit ships its own libmpv binaries through media_kit_libs_*,
//     so a fresh user does NOT have to `apt install libmpv-dev` to make
//     the app work. Out-of-the-box experience matters more than any
//     individual feature.
//   - It supports the same set of platforms we care about (Android,
//     iOS, Linux, Windows, macOS) with a unified API.
//
// Responsibilities of this class:
//   - Maintain the playback queue and current index.
//   - Resolve each track's StreamInfo just-in-time and feed the right
//     URI to the player (P2P-or-HTTP via SourceResolver).
//   - Surface a unified PlaybackSnapshot for the UI.
//   - Record anonymous play events through the repository.
//
// Background / lock-screen integration is a v0.2 concern (audio_service);
// MVP just needs solid in-app playback.
import 'dart:async';

// Hide media_kit's `Track` to avoid clashing with domain.Track.
import 'package:media_kit/media_kit.dart' hide Track;

import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../torrent/source_resolver.dart';

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
  PlaybackSnapshot _snap = PlaybackSnapshot.empty;

  Stream<PlaybackSnapshot> get snapshots => _snapshotCtrl.stream;
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
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _snapshotCtrl.close();
  }

  Future<void> _loadAndPlayCurrent() async {
    final track = _snap.current;
    if (track == null) return;

    final info = await _repo.resolveStream(track.id);
    final resolved = await _resolver.resolve(info);

    await _player.open(Media(resolved.uri.toString()));
    _emit(_snap.copyWith(usingP2P: resolved.usingP2P));

    unawaited(_repo.recordPlay(track.id));
  }

  void _wirePlayerEvents() {
    _subs.add(_player.stream.playing.listen((p) {
      _emit(_snap.copyWith(playing: p));
    }));
    _subs.add(_player.stream.position.listen((p) {
      _emit(_snap.copyWith(position: p));
    }));
    _subs.add(_player.stream.duration.listen((d) {
      _emit(_snap.copyWith(duration: d));
    }));
    _subs.add(_player.stream.buffer.listen((b) {
      _emit(_snap.copyWith(bufferedPosition: b));
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) unawaited(next());
    }));
  }

  void _emit(PlaybackSnapshot s) {
    _snap = s;
    if (!_snapshotCtrl.isClosed) _snapshotCtrl.add(s);
  }
}
