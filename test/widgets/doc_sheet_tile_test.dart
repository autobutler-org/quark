import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/doc_sheet_tile.dart';

/// #2276: a right-click on a Docs or Sheets row opens the menu its three-dot
/// button does.
void main() {
  const path = 'reports/budget.qsheet';
  final rename = find.byKey(const ValueKey('doc_sheet_rename_$path'));

  Future<void> pumpTile(WidgetTester tester, {VoidCallback? onRename}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocSheetTile(
              relPath: path,
              deviceName: 'Data',
              showDevice: false,
              onTap: () {},
              onRename: onRename,
            ),
          ),
        ),
      );

  testWidgets('a right-click opens Rename, like the button', (tester) async {
    var renamed = 0;
    await pumpTile(tester, onRename: () => renamed++);

    await tester.tap(find.byKey(const ValueKey('doc_sheet_menu_$path')));
    await tester.pumpAndSettle();
    expect(rename, findsOneWidget);
    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byType(ListTile)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(rename);
    await tester.pumpAndSettle();

    expect(renamed, 1);
  });

  testWidgets('a row with no actions opens nothing', (tester) async {
    await pumpTile(tester);

    await tester.tapAt(
      tester.getCenter(find.byType(ListTile)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<int>), findsNothing);
  });
}
