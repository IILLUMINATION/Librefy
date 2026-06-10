// Audio-related Riverpod wiring.
//
// The service is created once per app lifetime and disposed on shutdown.
// Widgets observe [playbackSnapshotProvider] for reactive playback state.
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/common/p2p_intro_dialog.dart';
import '../state/providers.dart';
import '../torrent/libtorrent_service.dart';
import '../torrent/source_resolver.dart';
import '../torrent/torrent_service.dart';
import 'audio_player_service.dart';

/// The active TorrentService. Resolves asynchronously:
///   1. Try LibtorrentService (native peer delivery).
///   2. Fall back to HttpOnlyTorrentService when the native lib is
///      missing (web build, unsupported platform, .so not bundled in
///      this build, …) so the rest of the app keeps working — the user
///      just won't be able to play magnet-only tracks.
final torrentServiceProvider = FutureProvider<TorrentService>((ref) async {
  final native = await LibtorrentService.tryInit();
  if (native != null) {
    ref.onDispose(native.dispose);
    return native;
  }
  dev.log('falling back to HttpOnlyTorrentService',
      name: 'librefy.torrent');
  return const HttpOnlyTorrentService();
});

/// Synchronous accessor used by [SourceResolver]. Awaits the async
/// torrent provider, defaulting to HttpOnly while it boots. Also honors
/// the user's "Enable peer delivery" preference — if they turned it off,
/// we serve the safe stub regardless of native lib availability.
final _activeTorrentServiceProvider = Provider<TorrentService>((ref) {
  final enabled = ref.watch(p2pEnabledProvider);
  if (!enabled) return const HttpOnlyTorrentService();
  return ref.watch(torrentServiceProvider).maybeWhen(
        data: (svc) => svc,
        orElse: () => const HttpOnlyTorrentService(),
      );
});

final sourceResolverProvider = Provider<SourceResolver>((ref) {
  return SourceResolver(ref.watch(_activeTorrentServiceProvider));
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

/// Stream of recoverable playback / resolution errors. Pipe into a
/// SnackBar listener so users see what went wrong instead of silent
/// "nothing is playing".
final playbackErrorProvider = StreamProvider<PlaybackError>((ref) {
  final svc = ref.watch(audioPlayerServiceProvider);
  return svc.errors;
});
