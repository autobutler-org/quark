import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Picking someone to message privately (#2497): the people listed, who is
/// picked passed in, and start enabled only with someone picked.
void main() {
  const bob = PrincipalItem(kind: PrincipalKind.user, id: 8, name: 'bob');
  const cy = PrincipalItem(kind: PrincipalKind.user, id: 9, name: 'cy');

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<List<String>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    List<PrincipalItem> people = const [bob, cy],
    PrincipalItem? selected,
    bool isLoading = false,
    String? loadError,
    bool isSubmitting = false,
    String? error,
  }) async {
    final log = <String>[];
    await pumpAt(
      tester,
      QuarkStartConversationDialog(
        people: people,
        selected: selected,
        isLoading: isLoading,
        loadError: loadError,
        isSubmitting: isSubmitting,
        error: error,
        onSelected: (p) => log.add('select ${p.name}'),
        onStart: () => log.add('start'),
        onCancel: () => log.add('cancel'),
      ),
      size: size,
    );
    return log;
  }

  testBothViewports('says it makes a private channel, and lists people', (
    tester,
    size,
  ) async {
    final log = await pumpDialog(tester, size: size);

    expect(find.text('Message someone'), findsOneWidget);
    expect(find.textContaining('private channel'), findsOneWidget);
    expect(key('principal_option_user_8'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(key('start_conversation_submit')).onPressed,
      isNull,
      reason: 'no one picked yet',
    );

    await tester.ensureVisible(key('principal_option_user_9'));
    await tester.tap(key('principal_option_user_9'));
    await tester.tap(key('start_conversation_cancel'));
    expect(log, ['select cy', 'cancel']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts with someone picked', (tester) async {
    final log = await pumpDialog(tester, selected: bob);

    await tester.tap(key('start_conversation_submit'));
    expect(log, ['start']);
  });

  testWidgets('shows loading, a load error, and no one else', (tester) async {
    await pumpDialog(tester, isLoading: true, people: const []);
    expect(find.byType(QuarkLoader), findsOneWidget);

    await pumpDialog(tester, loadError: "Couldn't load people.");
    expect(find.text("Couldn't load people."), findsOneWidget);
    expect(key('principal_option_user_8'), findsNothing);

    await pumpDialog(tester, people: const []);
    expect(find.textContaining('No one else'), findsOneWidget);
  });

  testWidgets('disables both buttons while starting, and shows a refusal', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      selected: bob,
      isSubmitting: true,
      error: 'Something went wrong.',
    );

    expect(
      tester.widget<FilledButton>(key('start_conversation_submit')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(key('start_conversation_cancel')).onPressed,
      isNull,
    );
    expect(find.text('Something went wrong.'), findsOneWidget);
  });
}
