import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/account_request_decision.dart';

/// One account request decision as the Quark's history lists it (#2730).
void main() {
  test('reads an approval, with the time in local time', () {
    final decision = AccountRequestDecision.fromJson(const {
      'username': 'grace',
      'outcome': 'approved',
      'decidedBy': 'ada',
      'decidedAt': '2026-10-09T11:23:39Z',
    });

    expect(decision.username, 'grace');
    expect(decision.approved, isTrue);
    expect(decision.decidedBy, 'ada');
    expect(decision.decidedAt.isUtc, isFalse);
    expect(decision.decidedAt, DateTime.utc(2026, 10, 9, 11, 23, 39).toLocal());
  });

  test('reads a denial', () {
    final decision = AccountRequestDecision.fromJson(const {
      'username': 'eli',
      'outcome': 'denied',
      'decidedBy': 'ada',
      'decidedAt': '2026-10-09T11:23:39Z',
    });

    expect(decision.approved, isFalse);
  });

  test('missing fields fall back rather than throw', () {
    final decision = AccountRequestDecision.fromJson(const {});

    expect(decision.username, '');
    expect(decision.approved, isFalse);
    expect(decision.decidedBy, '');
    expect(decision.decidedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
