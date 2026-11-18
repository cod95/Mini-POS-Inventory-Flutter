class AppException implements Exception {
  AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by login while an account is locked after repeated wrong attempts.
class LoginLockedException implements Exception {
  const LoginLockedException(this.seconds);

  final int seconds;

  @override
  String toString() => 'locked:$seconds';
}
