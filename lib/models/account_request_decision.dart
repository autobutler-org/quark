/// One decision an admin made about an account request, as
/// `GET /api/v0/admin/account-requests/history` lists it (#2730).
class AccountRequestDecision {
  const AccountRequestDecision({
    required this.username,
    required this.approved,
    required this.decidedBy,
    required this.decidedAt,
  });

  /// The account that asked.
  final String username;

  /// Whether the request was approved. False means it was denied.
  final bool approved;

  /// The username of the admin who decided.
  final String decidedBy;

  /// When they decided, in local time.
  final DateTime decidedAt;

  factory AccountRequestDecision.fromJson(Map<String, dynamic> json) =>
      AccountRequestDecision(
        username: json['username'] as String? ?? '',
        approved: json['outcome'] == 'approved',
        decidedBy: json['decidedBy'] as String? ?? '',
        decidedAt:
            (DateTime.tryParse(json['decidedAt'] as String? ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0))
                .toLocal(),
      );
}
