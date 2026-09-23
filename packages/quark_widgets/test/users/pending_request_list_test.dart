import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Account requests on the Users page (#1908): each row approves or denies the
/// one account it names.
void main() {
  const requests = [
    UserAccountItem(username: 'bob', status: UserAccountStatus.pending),
    UserAccountItem(username: 'cy', status: UserAccountStatus.pending),
  ];

  testBothViewports('shows a spinner while loading and no rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const PendingRequestList(requests: requests, isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('request_row_bob')), findsNothing);
    expect(find.text('No requests waiting'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const PendingRequestList(requests: requests, error: 'Nope.'),
      size: size,
    );

    expect(find.text('Nope.'), findsOneWidget);
    expect(find.byKey(const ValueKey('request_row_bob')), findsNothing);
  });

  testBothViewports('says so when nobody is waiting', (tester, size) async {
    await pumpAt(tester, const PendingRequestList(requests: []), size: size);

    expect(find.text('No requests waiting'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('approves and denies the request that was tapped', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      PendingRequestList(
        requests: requests,
        onApprove: (u) => events.add('approve $u'),
        onDeny: (u) => events.add('deny $u'),
      ),
      size: size,
    );

    for (final request in requests) {
      final name = request.username;
      expect(find.byKey(ValueKey('request_row_$name')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('request_approve_bob')));
    await tester.tap(find.byKey(const ValueKey('request_deny_cy')));
    await tester.pump();

    expect(events, ['approve bob', 'deny cy']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a request in flight shows progress instead of buttons', (
    tester,
  ) async {
    await pumpAt(
      tester,
      PendingRequestList(
        requests: requests,
        busyUsernames: const {'bob'},
        onApprove: (_) {},
        onDeny: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('request_approve_bob')), findsNothing);
    expect(find.byKey(const ValueKey('request_approve_cy')), findsOneWidget);
  });

  testWidgets('no callbacks leaves the buttons disabled', (tester) async {
    await pumpAt(tester, const PendingRequestList(requests: requests));

    final approve = tester.widget<FilledButton>(
      find.byKey(const ValueKey('request_approve_bob')),
    );
    expect(approve.onPressed, isNull);
  });

  testBothViewports('survives a long name and a long list', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: PendingRequestList(
          requests: [
            for (var i = 0; i < 60; i++)
              UserAccountItem(
                username: 'request$i${'x' * 24}',
                status: UserAccountStatus.pending,
              ),
          ],
          onApprove: (_) {},
          onDeny: (_) {},
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(
        tester,
        const PendingRequestList(requests: requests),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      final detail = tester.widget<Text>(
        find.text('Waiting for approval').first,
      );
      expect(detail.style?.color, tokens.mutedForeground);
    });
  }
}
