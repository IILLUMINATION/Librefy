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

class SourceResolver {
  SourceResolver(this._torrent);
  final TorrentService _torrent;

  Future<ResolvedSource> resolve(StreamInfo info) async {
    final hasMagnet = info.magnet != null && info.magnet!.isNotEmpty;
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
    final http = info.httpUrl;
    if (http == null || http.isEmpty) {
      throw StateError('Track has no playable source');
    }
    return ResolvedSource(uri: Uri.parse(http), usingP2P: false);
  }
}
