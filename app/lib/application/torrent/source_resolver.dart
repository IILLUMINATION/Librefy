// SourceResolver picks the best audio source for a track:
//
//   1. If a magnet is available AND the torrent layer supports peer
//      delivery, ask the torrent layer to open it and return its local
//      streaming URI.
//   2. Otherwise fall back to the HTTP URL returned by the backend.
//
// Whatever this function returns is fed straight to just_audio.
//
// This is the ONLY place in the player pipeline that knows magnets exist.
// just_audio talks to HTTP(s)/file URIs only, which is exactly what the
// torrent layer exposes via its local proxy.
import 'dart:developer' as dev;

import '../../domain/entities/stream_info.dart';
import 'torrent_service.dart';

const _logTag = 'librefy.resolver';

class ResolvedSource {
  ResolvedSource({
    required this.uri,
    required this.usingP2P,
    this.session,
  });
  final Uri uri;
  final bool usingP2P;
  final TorrentSession? session;
}

/// Thrown when a track has no usable source for the current build.
/// Carries enough context for the UI to show actionable copy.
class NoPlayableSourceError implements Exception {
  NoPlayableSourceError({required this.message});
  final String message;
  @override
  String toString() => message;
}

class SourceResolver {
  /// Accepts an async [TorrentService] factory rather than a ready
  /// instance: on Android (and slow Linux installs) the native libtorrent
  /// session takes a few hundred ms to spin up after launch, and a user
  /// who taps "play" during that window must not get a premature
  /// HttpOnly fallback — that's what produced "This track is P2P-only"
  /// errors right after app start even though native support was
  /// available a heartbeat later.
  ///
  /// The factory may return [HttpOnlyTorrentService] once it's certain
  /// native delivery is unavailable for this run (init failed or user
  /// disabled P2P). The resolver awaits the factory before checking
  /// [TorrentService.supportsPeerDelivery].
  SourceResolver(Future<TorrentService> Function() torrentFactory)
      : _torrentFactory = torrentFactory;

  final Future<TorrentService> Function() _torrentFactory;

  Future<ResolvedSource> resolve(StreamInfo info) async {
    final hasMagnet = info.magnet != null && info.magnet!.isNotEmpty;
    final http = info.httpUrl;
    final hasHttp = http != null && http.isNotEmpty;

    final torrent = await _torrentFactory();
    dev.log(
      'resolve: hasMagnet=$hasMagnet hasHttp=$hasHttp '
      'torrent=${torrent.runtimeType} supportsP2P=${torrent.supportsPeerDelivery}',
      name: _logTag,
    );

    if (hasMagnet && torrent.supportsPeerDelivery) {
      try {
        final session = await torrent.openMagnet(
          info.magnet!,
          fileIndex: info.fileIndex,
        );
        return ResolvedSource(
          uri: session.localUri,
          usingP2P: true,
          session: session,
        );
      } catch (e, st) {
        // Don't swallow silently — diagnosing "P2P-only" errors without
        // knowing why the native engine refused the magnet is painful.
        dev.log(
          'openMagnet failed, will try HTTP fallback: $e',
          name: _logTag,
          error: e,
          stackTrace: st,
        );
      }
    }

    if (hasHttp) {
      return ResolvedSource(uri: Uri.parse(http), usingP2P: false);
    }

    // Magnet exists but the current build can't open it, and there's
    // no HTTP fallback. Be loud and specific so the user/operator can
    // fix it (either add a streamUrl, or wait for the libtorrent build).
    if (hasMagnet) {
      // Distinguish the two failure modes: native engine absent vs.
      // native engine present but couldn't open the magnet. The
      // operator's fix is different for each.
      final reason = torrent.supportsPeerDelivery
          ? 'the torrent engine could not open this magnet (no metadata, no peers, or invalid magnet)'
          : 'the torrent engine is not available on this device';
      throw NoPlayableSourceError(
        message:
            'Этот трек доступен только через P2P (magnet), но $reason, '
            'а HTTP-источника у трека нет. Добавьте streamUrl в админ-панели '
            'или подождите интеграцию libtorrent (v0.2).',
      );
    }
    throw NoPlayableSourceError(
      message: 'У трека нет ни streamUrl, ни magnet — нечего воспроизводить.',
    );
  }
}
