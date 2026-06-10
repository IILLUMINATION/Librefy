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

/// Why the native libtorrent engine wasn't used. Surfaced to the UI so
/// settings/snackbars can explain "P2P unavailable" instead of leaving
/// the user staring at a generic playback error.
enum P2pUnavailableReason {
  /// Native engine is up and running.
  none,
  /// User disabled peer delivery in settings.
  userDisabled,
  /// Native .so failed to load (missing for this ABI, dlopen error, …).
  nativeUnavailable,
  /// .so loaded but session creation failed at runtime.
  initFailed,
}

final p2pUnavailableReasonProvider =
    StateProvider<P2pUnavailableReason>((_) => P2pUnavailableReason.none);

/// The active TorrentService. Resolves asynchronously:
///   1. Try LibtorrentService (native peer delivery).
///   2. Fall back to HttpOnlyTorrentService when the native lib is
///      missing (web build, unsupported platform, .so not bundled in
///      this build, …) so the rest of the app keeps working — the user
///      just won't be able to play magnet-only tracks.
final torrentServiceProvider = FutureProvider<TorrentService>((ref) async {
  try {
    final native = await LibtorrentService.tryInit();
    if (native != null) {
      ref.onDispose(native.dispose);
      ref.read(p2pUnavailableReasonProvider.notifier).state =
          P2pUnavailableReason.none;
      return native;
    }
    // tryInit returns null for two distinct reasons: dlopen failure or
    // ltCreate failure. Both already log internally; here we only have
    // to surface the fact-of-unavailability to the UI.
    dev.log(
      'LibtorrentService.tryInit returned null → falling back to '
      'HttpOnlyTorrentService. Magnet-only tracks will fail.',
      name: 'librefy.torrent',
      level: 900, // WARNING
    );
    ref.read(p2pUnavailableReasonProvider.notifier).state =
        P2pUnavailableReason.nativeUnavailable;
  } catch (e, st) {
    dev.log('LibtorrentService.tryInit threw: $e — using HttpOnly stub',
        name: 'librefy.torrent', error: e, stackTrace: st, level: 1000);
    ref.read(p2pUnavailableReasonProvider.notifier).state =
        P2pUnavailableReason.initFailed;
  }
  return const HttpOnlyTorrentService();
});

/// Async accessor used by [SourceResolver]. Awaits the real native
/// service initialization before falling back, so a user who taps play
/// during the ~100–500ms window while libtorrent is spinning up doesn't
/// get an "P2P-only, no engine" error.
///
/// Honors the user's "Enable peer delivery" preference — if they turned
/// it off, we short-circuit to the HttpOnly stub without waiting for
/// native init.
Future<TorrentService> _resolveTorrentService(Ref ref) async {
  final enabled = ref.read(p2pEnabledProvider);
  if (!enabled) {
    dev.log('P2P disabled by user → HttpOnly stub', name: 'librefy.torrent');
    ref.read(p2pUnavailableReasonProvider.notifier).state =
        P2pUnavailableReason.userDisabled;
    return const HttpOnlyTorrentService();
  }
  try {
    final svc = await ref.read(torrentServiceProvider.future);
    dev.log('active torrent service: ${svc.runtimeType} '
        '(supportsP2P=${svc.supportsPeerDelivery})',
        name: 'librefy.torrent');
    return svc;
  } catch (e, st) {
    dev.log('torrentServiceProvider failed: $e — using HttpOnly stub',
        name: 'librefy.torrent', error: e, stackTrace: st, level: 1000);
    ref.read(p2pUnavailableReasonProvider.notifier).state =
        P2pUnavailableReason.initFailed;
    return const HttpOnlyTorrentService();
  }
}

final sourceResolverProvider = Provider<SourceResolver>((ref) {
  return SourceResolver(() => _resolveTorrentService(ref));
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
