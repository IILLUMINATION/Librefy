// A playable track. Identity is the namespaced [id] returned by the
// backend (e.g. "catalog:abc123" or "ia:LiveSet-2009"); equality is
// based on it.
import 'package:flutter/foundation.dart';

import 'license.dart';

@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.license,
    required this.provider,
    this.album,
    this.artworkUrl,
    this.streamUrl,
    this.magnet,
    this.infoHash,
    this.attribution,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final String? artworkUrl;
  final String? streamUrl;
  final String? magnet;
  final String? infoHash;
  final License license;
  final String? attribution;
  final List<String> tags;
  final String provider;

  /// True when the track can be delivered via peer-assisted P2P.
  bool get hasP2P => magnet != null && magnet!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Track && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
