// Thin Dio wrapper around the librefyd REST surface. All HTTP details
// (base URL, timeouts, error mapping) live here; repositories never
// touch Dio directly.
import 'package:dio/dio.dart';

import '../../core/error/failures.dart';
import '../models/track_dto.dart';

class LibrefyApi {
  LibrefyApi(this._dio);

  final Dio _dio;

  factory LibrefyApi.withBaseUrl(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );
    return LibrefyApi(dio);
  }

  Future<List<PlaylistDto>> featured({int limit = 10}) async {
    final res = await _get('/api/v1/featured', query: {'limit': limit});
    final list = (res['playlists'] as List?) ?? const [];
    return list
        .map((e) => PlaylistDto.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<TrackDto>> trending({int limit = 20}) async {
    final res = await _get('/api/v1/trending', query: {'limit': limit});
    final list = (res['tracks'] as List?) ?? const [];
    return list
        .map((e) => TrackDto.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> search(String q, {int limit = 20}) =>
      _get('/api/v1/search', query: {'q': q, 'limit': limit});

  Future<TrackDto> getTrack(String id) async {
    final res = await _get('/api/v1/tracks/$id');
    return TrackDto.fromJson(res);
  }

  Future<StreamInfoDto> resolveStream(String id) async {
    final res = await _get('/api/v1/tracks/$id/stream');
    return StreamInfoDto.fromJson(res);
  }

  Future<Map<String, dynamic>> getPlaylist(String id) =>
      _get('/api/v1/playlists/$id');

  Future<void> recordPlay(String id) async {
    try {
      await _dio.post<void>('/api/v1/tracks/$id/play');
    } on DioException {
      // Best-effort: stats failures must never interrupt playback.
    }
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, Object?>? query}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Failure _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const NetworkFailure('Connection timed out');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 404) return const NotFoundFailure();
        return ServerFailure('Server error ($code)');
      case DioExceptionType.connectionError:
        return const NetworkFailure('Network unavailable');
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return NetworkFailure(e.message ?? 'Network error');
    }
  }
}
