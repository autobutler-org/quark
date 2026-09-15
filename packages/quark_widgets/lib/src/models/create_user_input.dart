import 'package:flutter/foundation.dart';

/// What [CreateUserDialog] hands back: the new account's username and
/// password, and whether to give it a private folder.
@immutable
class CreateUserInput {
  /// Creates the input for a new account named [username].
  const CreateUserInput({
    required this.username,
    required this.password,
    this.createFolder = true,
  });

  /// The username, already checked against the Quark's rules.
  final String username;

  /// The initial password, at least 8 characters.
  final String password;

  /// Whether to create a folder named after the account that only it and the
  /// admins can open.
  final bool createFolder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateUserInput &&
          other.username == username &&
          other.password == password &&
          other.createFolder == createFolder;

  @override
  int get hashCode => Object.hash(username, password, createFolder);
}
