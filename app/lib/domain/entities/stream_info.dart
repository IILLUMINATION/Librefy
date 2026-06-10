// StreamInfo is the resolved delivery descriptor for a track. The audio
// pipeline picks the best transport: prefer [magnet] when peer-assisted
// delivery is wired up, otherwise fall back to [httpUrl].
import 'package:flutter/foundation.dart';

@immutable
class StreamInfo {
  const StreamInfo({
    this.httpUrl,
    this.magnet,
    this.infoHash,
    this.mimeType = 'audio/mpeg',
  });

  final String? httpUrl;
  final String? magnet;
  final String? infoHash;
  final String mimeType;

  bool get hasAnySource =>
      (httpUrl != null && httpUrl!.isNotEmpty) ||
      (magnet != null && magnet!.isNotEmpty);
}
