import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/settings_account_tab.dart';

/// #2474: a member who opened Settings → Account found Sign out and a row
/// that only led to deleting their account, with no word on who manages
/// accounts. The tab now says an admin does, and gives an admin a row to the
/// Users page where that happens.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final usersRow = find.byKey(const ValueKey('settings_account_users'));
  final adminNote = find.byKey(const ValueKey('settings_account_admin_note'));

  Future<List<String>> pumpTab(
    WidgetTester tester, {
    required bool isAdmin,
    Size size = wideViewport,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsAccountTab(
            signedIn: true,
            isAdmin: isAdmin,
            onSignOut: () => calls.add('sign out'),
            onOpenAccountAndData: () => calls.add('account and data'),
            onOpenUsers: () => calls.add('users'),
          ),
        ),
      ),
    );
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('a member is told an admin manages accounts at $size', (
      tester,
    ) async {
      await pumpTab(tester, isAdmin: false, size: size);

      expect(tester.takeException(), isNull);
      expect(adminNote, findsOneWidget);
      expect(find.text('Accounts are managed by an admin'), findsOneWidget);
      expect(usersRow, findsNothing);
    });

    testWidgets('an admin gets a row to Users at $size', (tester) async {
      final calls = await pumpTab(tester, isAdmin: true, size: size);

      expect(tester.takeException(), isNull);
      expect(adminNote, findsNothing);
      await tester.ensureVisible(usersRow);
      await tester.tap(usersRow);
      expect(calls, ['users']);
    });
  }
}
