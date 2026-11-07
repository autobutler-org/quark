import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/storage_devices/restore_files_dialog.dart';

/// The restore confirm step: it warns that deleted files come back, and pops
/// with whether a gone drive's files go to built-in storage.
void main() {
  /// Opens the dialog; the returned list receives what it pops with.
  Future<List<bool?>> open(WidgetTester tester) async {
    final popped = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped.add(
              await showDialog<bool>(
                context: context,
                builder: (_) => const RestoreFilesDialog(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('warns that files deleted since come back', (tester) async {
    await open(tester);
    expect(find.textContaining('deleted since'), findsOneWidget);
  });

  testWidgets('confirm pops false by default', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(popped, [false]);
  });

  testWidgets('confirm pops true once built-in storage is chosen', (
    tester,
  ) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_to_built_in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('restore_files_confirm')));
    await tester.pumpAndSettle();
    expect(popped, [true]);
  });

  testWidgets('cancel pops nothing', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(const ValueKey('restore_files_cancel')));
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });
}
