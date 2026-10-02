import 'package:flutter/foundation.dart';

/// One signed-in session of the user's account, as `GET /api/v0/auth/sessions`
/// lists it (#1663).
@immutable
class AuthSession {
  /// Creates a session description.
  const AuthSession({
    required this.id,
    required this.createdAt,
    required this.lastUsedAt,
    required this.current,
  });

  /// Reads one entry of `GET /api/v0/auth/sessions`.
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
    current: json['current'] as bool? ?? false,
  );

  /// What the Quark calls the session, which is what revoking it takes.
  final String id;

  /// When the session was signed in.
  final DateTime createdAt;

  /// When the session last renewed itself. The Quark debounces renewal, so
  /// this can trail the newest request.
  final DateTime lastUsedAt;

  /// Whether this is the session the app is using right now.
  final bool current;
}
