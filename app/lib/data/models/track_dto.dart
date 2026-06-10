// Lightweight DTOs that mirror the JSON shape returned by librefyd.
// Kept hand-written (instead of code-gen) to keep the MVP build pipeline
// simple — no build_runner needed to ship.
import '../../domain/entities/license.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/stream_info.dart';
import '../../domain/entities/track.dart';

class TrackDto {
  TrackDto.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        title = json['title'] as String? ?? '',
        artist = json['artist'] as String? ?? '',
        album = json['album'] as String?,
        durationMs = (json['durationMs'] as num?)?.toInt() ?? 0,
        artworkUrl = json['artworkUrl'] as String?,
        streamUrl = json['streamUrl'] as String?,
        magnet = json['magnet'] as String?,
        infoHash = json['infoHash'] as String?,
        attribution = json['attribution'] as String?,
        provider = json['provider'] as String? ?? 'unknown',
        tags = (json['tags'] as List?)?.cast<String>() ?? const <String>[],
        license = _licenseFromJson(json['license']);

  final String id;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? artworkUrl;
  final String? streamUrl;
  final String? magnet;
  final String? infoHash;
  final String? attribution;
  final List<String> tags;
  final String provider;
  final License license;

  Track toDomain() => Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: Duration(milliseconds: durationMs),
        artworkUrl: artworkUrl,
        streamUrl: streamUrl,
        magnet: magnet,
        infoHash: infoHash,
        license: license,
        attribution: attribution,
        tags: tags,
        provider: provider,
      );

  static License _licenseFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return License.unknown;
    return License(
      code: raw['code'] as String? ?? 'UNKNOWN',
      name: raw['name'] as String? ?? 'Unknown',
      url: raw['url'] as String?,
    );
  }
}

class PlaylistDto {
  PlaylistDto.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        title = json['title'] as String? ?? '',
        description = json['description'] as String?,
        artworkUrl = json['artworkUrl'] as String?,
        curated = json['curated'] as bool? ?? false,
        trackIds = (json['trackIds'] as List?)?.cast<String>() ?? const <String>[];

  final String id;
  final String title;
  final String? description;
  final String? artworkUrl;
  final bool curated;
  final List<String> trackIds;

  Playlist toDomain() => Playlist(
        id: id,
        title: title,
        description: description,
        artworkUrl: artworkUrl,
        curated: curated,
        trackIds: trackIds,
      );
}

class StreamInfoDto {
  StreamInfoDto.fromJson(Map<String, dynamic> json)
      : httpUrl = json['httpUrl'] as String?,
        magnet = json['magnet'] as String?,
        infoHash = json['infoHash'] as String?,
        fileIndex = (json['fileIndex'] as num?)?.toInt() ?? 0,
        mimeType = json['mimeType'] as String? ?? 'audio/mpeg';

  final String? httpUrl;
  final String? magnet;
  final String? infoHash;
  final int fileIndex;
  final String mimeType;

  StreamInfo toDomain() => StreamInfo(
        httpUrl: httpUrl,
        magnet: magnet,
        infoHash: infoHash,
        fileIndex: fileIndex,
        mimeType: mimeType,
      );
}
