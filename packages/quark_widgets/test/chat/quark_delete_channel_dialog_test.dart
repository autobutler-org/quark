import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Deleting a chat channel (#2422) can't be undone, so the confirm button
/// waits for the channel's exact name.
void main() {
  Future<List<String>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    bool isSubmitting = false,
    String? error,
  }) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkDeleteChannelDialog(
        channelName: 'design',
        isSubmitting: isSubmitting,
        error: error,
        onConfirm: () => events.add('confirm'),
        onCancel: () => events.add('cancel'),
      ),
      size: size,
    );
    return events;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  FilledButton confirm(WidgetTester tester) =>
      tester.widget<FilledButton>(key('delete_channel_confirm'));

  testBothViewports('confirms only once the name is typed', (
    tester,
    size,
  ) async {
    final events = await pumpDialog(tester, size: size);
    expect(find.text('Delete #design?'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);

    await tester.enterText(key('delete_channel_field'), 'Design');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull, reason: 'case matters');

    await tester.enterText(key('delete_channel_field'), 'design');
    await tester.pump();
    await tester.tap(key('delete_channel_confirm'));
    expect(events, ['confirm']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancels, and shows a refusal', (tester) async {
    final events = await pumpDialog(tester, error: "Couldn't delete it.");

    expect(find.text("Couldn't delete it."), findsOneWidget);
    await tester.tap(key('delete_channel_cancel'));
    expect(events, ['cancel']);
  });

  testWidgets('disables both buttons while deleting', (tester) async {
    await pumpDialog(tester, isSubmitting: true);

    await tester.enterText(key('delete_channel_field'), 'design');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull);
    expect(
      tester.widget<TextButton>(key('delete_channel_cancel')).onPressed,
      isNull,
    );
  });
}
