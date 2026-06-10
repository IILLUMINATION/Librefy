// AudioPlayerService wraps just_audio with a Librefy-specific queue and
// source-resolution flow. The widget tree never instantiates a
// JustAudioPlayer directly — it talks to this service through Riverpod.
//
// Responsibilities:
//   - Maintain the playback queue and current index.
//   - Resolve each track's [StreamInfo] just-in-time and feed the right
//     URI to just_audio (P2P-or-HTTP via [SourceResolver]).
//   - Surface a unified [PlaybackState] for the UI.
//   - Record anonymous play events through the repository.
//
// Background playback (lockscreen / notification) is wired up at the
// app entry point via `just_audio_background`.
import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../torrent/source_resolver.dart';

/// Snapshot of player state, kept transport-agnostic so the UI does
/// not need to import just_audio.
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
    AudioPlayer? player,
  })  : _repo = repository,
        _resolver = resolver,
        _player = player ?? AudioPlayer() {
    _wirePlayerEvents();
  }

  final CatalogRepository _repo;
  final SourceResolver _resolver;
  final AudioPlayer _player;

  final _snapshotCtrl = StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot _snap = PlaybackSnapshot.empty;

  Stream<PlaybackSnapshot> get snapshots => _snapshotCtrl.stream;
  PlaybackSnapshot get current => _snap;

  Future<void> playTrack(Track track) async {
    await playQueue([track], startIndex: 0);
  }

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
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> dispose() async {
    await _player.dispose();
    await _snapshotCtrl.close();
  }

  Future<void> _loadAndPlayCurrent() async {
    final track = _snap.current;
    if (track == null) return;

    final info = await _repo.resolveStream(track.id);
    final resolved = await _resolver.resolve(info);

    await _player.setAudioSource(AudioSource.uri(resolved.uri));
    _emit(_snap.copyWith(usingP2P: resolved.usingP2P));

    unawaited(_repo.recordPlay(track.id));
    await _player.play();
  }

  void _wirePlayerEvents() {
    _player.playerStateStream.listen((s) {
      _emit(_snap.copyWith(playing: s.playing));
      if (s.processingState == ProcessingState.completed) {
        unawaited(next());
      }
    });
    _player.positionStream.listen((p) => _emit(_snap.copyWith(position: p)));
    _player.bufferedPositionStream
        .listen((b) => _emit(_snap.copyWith(bufferedPosition: b)));
    _player.durationStream
        .listen((d) => _emit(_snap.copyWith(duration: d ?? Duration.zero)));
  }

  void _emit(PlaybackSnapshot s) {
    _snap = s;
    if (!_snapshotCtrl.isClosed) _snapshotCtrl.add(s);
  }
}
