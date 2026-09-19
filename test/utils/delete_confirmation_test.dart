import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/trash_config.dart';

/// Regression coverage for #2049: deleting a file has moved it to the trash
/// since #1844, but the confirmation still read "Delete «name»?" — so the one
/// screen that decides whether a person clicks Delete never mentioned that the
/// item is recoverable, and the image viewer's own copy claimed the opposite.
///
/// The invariant these tests pin: the confirmation names the trash and the
/// window the backend actually keeps the item for.
void main() {
  Future<void> openConfirm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => confirmDelete(context, 'budget.xlsx'),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the confirmation says the item moves to the trash', (
    tester,
  ) async {
    await openConfirm(tester);

    expect(find.text('Move to Trash?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Move to Trash'), findsOneWidget);
    expect(find.textContaining('budget.xlsx'), findsOneWidget);
  });

  testWidgets('the confirmation names the restore window', (tester) async {
    await openConfirm(tester);

    expect(
      find.textContaining('${TrashConfig.retentionDays} days'),
      findsOneWidget,
    );
  });

  testWidgets('the confirmation never calls the delete permanent', (
    tester,
  ) async {
    await openConfirm(tester);

    expect(find.textContaining('permanently'), findsNothing);
    expect(find.textContaining('cannot be undone'), findsNothing);
  });
}
