import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The confirmation in front of a delete. Generic, so its keys come from the
/// caller's prefix (#1909).
void main() {
  Widget dialog(List<String> events, {String confirmLabel = 'Delete'}) =>
      ConfirmDeleteDialog(
        title: 'Delete bob?',
        body: 'Their files stay on this Quark and become yours.',
        keyPrefix: 'delete_user',
        confirmLabel: confirmLabel,
        onConfirm: () => events.add('confirm'),
        onCancel: () => events.add('cancel'),
      );

  testBothViewports('shows the caller copy', (tester, size) async {
    await pumpAt(tester, dialog([]), size: size);

    expect(find.text('Delete bob?'), findsOneWidget);
    expect(
      find.text('Their files stay on this Quark and become yours.'),
      findsOneWidget,
    );
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('confirms and cancels through the prefixed keys', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, dialog(events), size: size);

    await tester.tap(find.byKey(const ValueKey('delete_user_cancel')));
    await tester.tap(find.byKey(const ValueKey('delete_user_confirm')));
    await tester.pump();

    expect(events, ['cancel', 'confirm']);
  });

  testWidgets('takes its own confirm label', (tester) async {
    await pumpAt(tester, dialog([], confirmLabel: 'Delete group'));

    expect(find.text('Delete group'), findsOneWidget);
  });

  testBothViewports('survives long copy', (tester, size) async {
    await pumpAt(
      tester,
      ConfirmDeleteDialog(
        title: 'Delete ${'a very long name ' * 6}?',
        body: 'Their files stay on this Quark. ' * 12,
        keyPrefix: 'delete_user',
        onConfirm: () {},
        onCancel: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the confirm button wears the error color', (
      tester,
    ) async {
      await pumpAt(tester, dialog([]), brightness: brightness);

      expect(tester.takeException(), isNull);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('delete_user_confirm')),
      );
      expect(
        button.style?.backgroundColor?.resolve(const <WidgetState>{}),
        tokens.error,
      );
    });
  }
}
