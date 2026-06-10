// Domain-level error taxonomy. Repositories and the UI catch [Failure]
// rather than concrete Dio/SocketException types.
sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure() : super('Not found');
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class PlaybackFailure extends Failure {
  const PlaybackFailure(super.message);
}
