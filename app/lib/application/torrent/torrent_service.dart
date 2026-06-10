// Torrent abstraction layer.
//
// Librefy's MVP ships HTTP-only audio delivery (see [HttpOnlyTorrentService]).
// The real libtorrent integration is intentionally left as a separate
// implementation that can be slotted in later via FFI without touching
// the player or repository code.
//
// Design contract:
//   - `resolveLocalUri(magnet)` returns a URI the audio player can hand
//     to just_audio as if it were a regular file/HTTP source.
//   - Implementations are responsible for *progressive* delivery: data
//     for the first audio pieces becomes readable as quickly as possible
//     so playback can start before the full file is downloaded.
//   - The player NEVER speaks the torrent protocol itself.
//
// Why an interface from day one:
//   - The choice of native engine (libtorrent on desktop, gomobile-bridged
//     anacrolix/torrent on Android, WebTorrent for the web build) can be
//     swapped per platform.
//   - The official build can ship the safe HTTP-only implementation and
//     refuse to load magnet URIs unless the user opted into a plugin.
import 'dart:async';

/// A handle returned by [TorrentService.openMagnet]. Dispose it when the
/// player no longer needs the source, otherwise resources keep flowing.
class TorrentSession {
  TorrentSession({
    required this.localUri,
    required this.dispose,
    this.stats = const Stream.empty(),
  });

  /// A URI just_audio can play (e.g. http://127.0.0.1:43210/stream/<hash>).
  final Uri localUri;

  /// Cancels the session; idempotent.
  final Future<void> Function() dispose;

  /// Optional progress stream (peers, download rate, buffered pieces).
  final Stream<TorrentStats> stats;
}

class TorrentStats {
  const TorrentStats({
    required this.peers,
    required this.downloadRateBps,
    required this.progress,
  });

  final int peers;
  final int downloadRateBps;
  /// [0.0, 1.0]
  final double progress;
}

abstract class TorrentService {
  /// Starts (or attaches to) the swarm identified by [magnet] and returns
  /// a [TorrentSession] whose [localUri] can be fed to the player.
  Future<TorrentSession> openMagnet(String magnet);

  /// Whether this implementation actually performs peer-assisted delivery.
  /// HTTP-only stubs return false so the resolver can fall back gracefully.
  bool get supportsPeerDelivery;
}

/// Default implementation: there is no torrent engine compiled in. The
/// resolver simply tells the caller "this isn't a thing here". The
/// resolver is expected to fall back to the HTTP URL in that case.
class HttpOnlyTorrentService implements TorrentService {
  const HttpOnlyTorrentService();

  @override
  bool get supportsPeerDelivery => false;

  @override
  Future<TorrentSession> openMagnet(String magnet) {
    throw UnsupportedError(
      'Peer-assisted delivery is not available in this build. '
      'Use the HTTP fallback URL instead.',
    );
  }
}
