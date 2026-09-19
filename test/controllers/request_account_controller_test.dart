import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/request_account_controller.dart';
import 'package:quark/utils/error_text.dart';

/// Requesting an account from the login page (#1908): form, then the recovery
/// phrase, then "request sent".
void main() {
  test('a sent request shows its recovery phrase', () async {
    final sent = <String>[];
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) async {
        sent.add('$username:$password');
        return 'apple banana cherry';
      },
    );
    var notified = 0;
    c.addListener(() => notified++);

    await c.submit(username: 'bob', password: 'hunter2hunter2');

    expect(sent, ['bob:hunter2hunter2']);
    expect(c.step, RequestAccountStep.phrase);
    expect(c.recoveryPhrase, 'apple banana cherry');
    expect(c.isSubmitting, isFalse);
    expect(c.error, isNull);
    expect(notified, 2);
  });

  test('a refused request stays on the form with the failure', () async {
    final refusal = MessageException(Errors.accessRequestsOff);
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) async =>
          throw refusal,
    );

    await c.submit(username: 'bob', password: 'hunter2hunter2');

    expect(c.step, RequestAccountStep.form);
    expect(c.error, same(refusal));
    expect(c.isSubmitting, isFalse);
    expect(c.recoveryPhrase, isNull);
  });

  test('a retry clears the last failure', () async {
    var fail = true;
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) async {
        if (fail) throw const ApiException(429);
        return 'phrase';
      },
    );

    await c.submit(username: 'bob', password: 'hunter2hunter2');
    expect(c.error, isNotNull);

    fail = false;
    await c.submit(username: 'bob', password: 'hunter2hunter2');
    expect(c.error, isNull);
    expect(c.step, RequestAccountStep.phrase);
  });

  test('a second submit while one is in flight sends nothing', () async {
    final gate = Completer<String>();
    var calls = 0;
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) {
        calls++;
        return gate.future;
      },
    );

    final first = c.submit(username: 'bob', password: 'hunter2hunter2');
    expect(c.isSubmitting, isTrue);
    await c.submit(username: 'bob', password: 'hunter2hunter2');
    gate.complete('phrase');
    await first;

    expect(calls, 1);
  });

  test('the phrase step only finishes once acknowledged', () async {
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) async =>
          'phrase',
    );
    await c.submit(username: 'bob', password: 'hunter2hunter2');

    c.finish();
    expect(c.step, RequestAccountStep.phrase);

    c.setAcknowledged(true);
    c.finish();
    expect(c.step, RequestAccountStep.sent);
  });

  test('a response landing after dispose is dropped', () async {
    final gate = Completer<String>();
    final c = RequestAccountController(
      requestAccount: ({required username, required password}) => gate.future,
    );

    final pending = c.submit(username: 'bob', password: 'hunter2hunter2');
    c.dispose();
    gate.complete('phrase');

    await expectLater(pending, completes);
  });
}
