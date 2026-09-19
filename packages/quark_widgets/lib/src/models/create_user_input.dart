import 'package:flutter/foundation.dart';

/// What [CreateUserDialog] hands back: the new account's username and
/// password.
@immutable
class CreateUserInput {
  /// Creates the input for a new account named [username].
  const CreateUserInput({required this.username, required this.password});

  /// The username, already checked against the Quark's rules.
  final String username;

  /// The initial password, at least 8 characters.
  final String password;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateUserInput &&
          other.username == username &&
          other.password == password;

  @override
  int get hashCode => Object.hash(username, password);
}
