abstract class AlfanousException implements Exception {
  final String message;

  const AlfanousException(this.message);

  @override
  String toString() => 'AlfanousException: $message';
}

class DatabaseInitializationException extends AlfanousException {
  const DatabaseInitializationException(String message) : super(message);

  @override
  String toString() => 'DatabaseInitializationException: $message';
}

class DatabaseNotFoundException extends AlfanousException {
  final String attemptedPath;

  const DatabaseNotFoundException(String message, this.attemptedPath)
      : super(message);

  @override
  String toString() =>
      'DatabaseNotFoundException: $message (Path: $attemptedPath)';
}

class QueryExecutionException extends AlfanousException {
  final Object originalError;

  const QueryExecutionException(String message, this.originalError)
      : super(message);

  @override
  String toString() =>
      'QueryExecutionException: $message\nDetails: $originalError';
}
