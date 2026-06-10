// Audio-related Riverpod wiring.
//
// The service is created once per app lifetime and disposed on shutdown.
// Widgets observe [playbackSnapshotProvider] for reactive playback state.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../torrent/source_resolver.dart';
import '../torrent/torrent_service.dart';
import 'audio_player_service.dart';

/// Swap this provider in tests / desktop builds to inject a different
/// TorrentService implementation (libtorrent FFI, WebTorrent, etc.).
final torrentServiceProvider = Provider<TorrentService>((ref) {
  return const HttpOnlyTorrentService();
});

final sourceResolverProvider = Provider<SourceResolver>((ref) {
  return SourceResolver(ref.watch(torrentServiceProvider));
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final svc = AudioPlayerService(
    repository: ref.watch(catalogRepositoryProvider),
    resolver: ref.watch(sourceResolverProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Reactive playback state. Seeded with the service's current snapshot
/// so widgets render instantly without waiting for the first event.
final playbackSnapshotProvider = StreamProvider.autoDispose((ref) {
  final svc = ref.watch(audioPlayerServiceProvider);
  return svc.snapshots;
});
