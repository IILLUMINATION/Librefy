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
import '../../domain/entities/stream_info.dart';
import 'torrent_service.dart';

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
  SourceResolver(this._torrent);
  final TorrentService _torrent;

  Future<ResolvedSource> resolve(StreamInfo info) async {
    final hasMagnet = info.magnet != null && info.magnet!.isNotEmpty;
    final http = info.httpUrl;
    final hasHttp = http != null && http.isNotEmpty;

    if (hasMagnet && _torrent.supportsPeerDelivery) {
      try {
        final session = await _torrent.openMagnet(info.magnet!);
        return ResolvedSource(
          uri: session.localUri,
          usingP2P: true,
          session: session,
        );
      } catch (_) {
        // Fall through to HTTP fallback.
      }
    }

    if (hasHttp) {
      return ResolvedSource(uri: Uri.parse(http), usingP2P: false);
    }

    // Magnet exists but the current build can't open it, and there's
    // no HTTP fallback. Be loud and specific so the user/operator can
    // fix it (either add a streamUrl, or wait for the libtorrent build).
    if (hasMagnet) {
      throw NoPlayableSourceError(
        message: 'This track is P2P-only (magnet). The current build has '
            'no torrent engine wired up — add a streamUrl in the admin '
            'panel, or wait for the libtorrent integration in v0.2.',
      );
    }
    throw NoPlayableSourceError(
      message: 'This track has no playable source (no streamUrl, no magnet).',
    );
  }
}
