// MusicProvider is the Flutter-side mirror of the backend's
// service.MusicProvider interface. Implementing this contract lets
// third-party plugins ship as packages that the user can side-load
// at their own risk; the official build only ships a single, remote-
// backed implementation that talks to a Librefy server.
//
// The interface is intentionally tiny so plugins remain easy to write
// and audit. ID conventions follow the backend: "<provider>:<localID>".
import '../entities/search_result.dart';
import '../entities/stream_info.dart';
import '../entities/track.dart';

abstract class MusicProvider {
  /// Stable identifier, e.g. "remote", "local-fs", "ia".
  String get name;

  /// Search across tracks, artists and playlists.
  Future<SearchResult> search(String query, {int limit = 20});

  /// Resolve a namespaced track ID to a full Track.
  Future<Track> getTrack(String id);

  /// Resolve a namespaced track ID to a delivery descriptor.
  Future<StreamInfo> getStream(String id);
}
