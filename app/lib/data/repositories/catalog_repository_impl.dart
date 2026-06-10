// CatalogRepositoryImpl is the production implementation backed by the
// remote librefyd HTTP API. It performs DTO -> Domain mapping and is the
// only file aware of the wire format used by the backend.
import '../../domain/entities/playlist.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/stream_info.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/librefy_api.dart';
import '../models/track_dto.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._api);

  final LibrefyApi _api;

  @override
  Future<List<Playlist>> featured({int limit = 10}) async {
    final dtos = await _api.featured(limit: limit);
    return dtos.map((e) => e.toDomain()).toList(growable: false);
  }

  @override
  Future<List<Track>> trending({int limit = 20}) async {
    final dtos = await _api.trending(limit: limit);
    return dtos.map((e) => e.toDomain()).toList(growable: false);
  }

  @override
  Future<SearchResult> search(String query, {int limit = 20}) async {
    final raw = await _api.search(query, limit: limit);
    final tracks = (raw['tracks'] as List?)
            ?.map((e) => TrackDto.fromJson(e as Map<String, dynamic>).toDomain())
            .toList(growable: false) ??
        const <Track>[];
    final playlists = (raw['playlists'] as List?)
            ?.map((e) => PlaylistDto.fromJson(e as Map<String, dynamic>).toDomain())
            .toList(growable: false) ??
        const <Playlist>[];
    return SearchResult(tracks: tracks, playlists: playlists);
  }

  @override
  Future<Track> getTrack(String id) async {
    final dto = await _api.getTrack(id);
    return dto.toDomain();
  }

  @override
  Future<StreamInfo> resolveStream(String id) async {
    final dto = await _api.resolveStream(id);
    return dto.toDomain();
  }

  @override
  Future<({Playlist playlist, List<Track> tracks})> getPlaylist(String id) async {
    final raw = await _api.getPlaylist(id);
    final pl = PlaylistDto.fromJson(raw['playlist'] as Map<String, dynamic>).toDomain();
    final tracks = (raw['tracks'] as List?)
            ?.map((e) => TrackDto.fromJson(e as Map<String, dynamic>).toDomain())
            .toList(growable: false) ??
        const <Track>[];
    return (playlist: pl, tracks: tracks);
  }

  @override
  Future<void> recordPlay(String id) => _api.recordPlay(id);
}
