import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/vault/vault_start_over_dialog.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3615: starting the vault over erases every saved login, so the dialog
/// asks for the login password and sends nothing until one is typed.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final passwordField = find.byKey(
    const ValueKey('vault_start_over_password_field'),
  );
  final confirm = find.byKey(const ValueKey('vault_start_over_confirm'));
  final cancel = find.byKey(const ValueKey('vault_start_over_cancel'));

  /// Pumps the dialog at [size]; [confirmed] and [canceled] record its
  /// callbacks.
  Future<void> pumpDialog(
    WidgetTester tester,
    Size size,
    List<String> confirmed,
    List<bool> canceled,
  ) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultStartOverDialog(
            onConfirm: confirmed.add,
            onCancel: () => canceled.add(true),
          ),
        ),
      ),
    );
  }

  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('confirms only with a typed password ($name)', (tester) async {
      final confirmed = <String>[];
      await pumpDialog(tester, size, confirmed, []);

      await tester.tap(confirm);
      await tester.pump();
      expect(confirmed, isEmpty);

      await tester.enterText(passwordField, 'hunter2');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();

      expect(confirmed, ['hunter2']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel calls back without a password', (tester) async {
    final confirmed = <String>[];
    final canceled = <bool>[];
    await pumpDialog(tester, wideViewport, confirmed, canceled);

    await tester.enterText(passwordField, 'hunter2');
    await tester.tap(cancel);
    await tester.pump();

    expect(canceled, [true]);
    expect(confirmed, isEmpty);
  });
}
