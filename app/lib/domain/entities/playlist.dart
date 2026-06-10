import 'package:flutter/foundation.dart';

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    required this.curated,
    this.description,
    this.artworkUrl,
    this.trackIds = const <String>[],
  });

  final String id;
  final String title;
  final String? description;
  final String? artworkUrl;
  final bool curated;
  final List<String> trackIds;
}
