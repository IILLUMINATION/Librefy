import 'package:flutter/foundation.dart';

import 'playlist.dart';
import 'track.dart';

@immutable
class SearchResult {
  const SearchResult({
    this.tracks = const <Track>[],
    this.playlists = const <Playlist>[],
  });

  final List<Track> tracks;
  final List<Playlist> playlists;

  bool get isEmpty => tracks.isEmpty && playlists.isEmpty;
}
