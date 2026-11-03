/// One account on the Quark, as `GET /api/v0/admin/users` lists it.
class UserAccount {
  const UserAccount({
    required this.id,
    required this.username,
    this.isAdmin = false,
    this.status = UserAccount.active,
    this.createdAt,
    this.shortRecoveryPhrase = false,
  });

  /// [status] of an account someone requested and no admin has approved.
  static const pending = 'pending';

  /// [status] of an account that can sign in.
  static const active = 'active';

  /// [status] of an account an admin turned off.
  static const disabled = 'disabled';

  final int id;
  final String username;
  final bool isAdmin;

  /// [pending], [active] or [disabled].
  final String status;

  /// When the account was created. Null when the Quark did not say.
  final DateTime? createdAt;

  /// Whether the account still holds a recovery phrase shorter than 16 words,
  /// or one of unknown length from before #3183, and should make a new one.
  /// False when the account has no recovery key.
  final bool shortRecoveryPhrase;

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    isAdmin: json['isAdmin'] as bool? ?? false,
    status: json['status'] as String? ?? active,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    shortRecoveryPhrase: json['shortRecoveryPhrase'] as bool? ?? false,
  );
}
