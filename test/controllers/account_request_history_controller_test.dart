import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/account_request_history_controller.dart';
import 'package:quark/models/account_request_decision.dart';
import 'package:quark/utils/error_text.dart';

/// The Recent decisions section's state (#2730).
void main() {
  final approved = AccountRequestDecision(
    username: 'grace',
    approved: true,
    decidedBy: 'ada',
    decidedAt: DateTime(2026, 10, 9),
  );
  final denied = AccountRequestDecision(
    username: 'eli',
    approved: false,
    decidedBy: 'ada',
    decidedAt: DateTime(2026, 10, 8),
  );

  test('loads the decisions in the order given', () async {
    final c = AccountRequestHistoryController(
      listHistory: () async => [approved, denied],
    );
    var notified = 0;
    c.addListener(() => notified++);

    await c.load();

    expect(c.hasLoaded, isTrue);
    expect(c.isLoading, isFalse);
    expect(c.error, isNull);
    expect(c.decisions, [approved, denied]);
    expect(notified, 2, reason: 'once to start, once to finish');
  });

  test('a failed first load says why and has no rows', () async {
    final c = AccountRequestHistoryController(
      listHistory: () async => throw const ApiException(403),
    );

    await c.load();

    expect(c.error, isA<ApiException>());
    expect(c.hasLoaded, isFalse);
    expect(c.isLoading, isFalse);
    expect(c.decisions, isEmpty);
  });

  test('a failed reload keeps the last decisions and says why', () async {
    Object? listError;
    final c = AccountRequestHistoryController(
      listHistory: () async {
        if (listError != null) throw listError;
        return [approved];
      },
    );
    await c.load();
    listError = const ApiException(500);

    await c.load();

    expect(c.error, isA<ApiException>());
    expect(c.hasLoaded, isTrue);
    expect(c.decisions, [approved]);

    listError = null;
    await c.load();

    expect(c.error, isNull);
  });

  test('a slow load cannot overwrite a newer one', () async {
    final slow = Completer<List<AccountRequestDecision>>();
    var first = true;
    final c = AccountRequestHistoryController(
      listHistory: () {
        if (first) {
          first = false;
          return slow.future;
        }
        return Future.value([approved, denied]);
      },
    );

    final stale = c.load();
    await c.load();
    slow.complete([denied]);
    await stale;

    expect(c.decisions, [approved, denied]);
    expect(c.isLoading, isFalse);
  });

  test('a load that finishes after dispose notifies nobody', () async {
    final slow = Completer<List<AccountRequestDecision>>();
    final c = AccountRequestHistoryController(listHistory: () => slow.future);

    final pending = c.load();
    c.dispose();
    slow.complete([approved]);

    await expectLater(pending, completes);
  });
}
