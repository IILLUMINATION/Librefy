// Catalog-side reads that go beyond MusicProvider: home screen content,
// curated playlists, anonymous play tracking.
import '../entities/playlist.dart';
import '../entities/search_result.dart';
import '../entities/stream_info.dart';
import '../entities/track.dart';

abstract class CatalogRepository {
  Future<List<Playlist>> featured({int limit = 10});
  Future<List<Track>> trending({int limit = 20});
  Future<SearchResult> search(String query, {int limit = 20});
  Future<Track> getTrack(String id);
  Future<StreamInfo> resolveStream(String id);
  Future<({Playlist playlist, List<Track> tracks})> getPlaylist(String id);
  Future<void> recordPlay(String id);
}
