import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/settings_account_tab.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2474: a member who opened Settings → Account found Sign out and a row
/// that only led to deleting their account, with no word on who manages
/// accounts. The tab now says an admin does, and gives an admin a row to the
/// Users page where that happens.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final usersRow = find.byKey(const ValueKey('settings_account_users'));
  final adminNote = find.byKey(const ValueKey('settings_account_admin_note'));
  final changePasswordRow = find.byKey(
    const ValueKey('settings_account_change_password'),
  );

  Future<List<String>> pumpTab(
    WidgetTester tester, {
    required bool isAdmin,
    bool signedIn = true,
    Size size = wideViewport,
  }) async {
    setViewport(tester, size);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsAccountTab(
            signedIn: signedIn,
            isAdmin: isAdmin,
            onSignOut: () => calls.add('sign out'),
            onChangePassword: () => calls.add('change password'),
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

    // #3022: changing a password is the account owner's to do, so the row is
    // there for a member as much as for an admin.
    for (final isAdmin in [false, true]) {
      testWidgets('${isAdmin ? 'an admin' : 'a member'} gets a Change '
          'password row at $size', (tester) async {
        final calls = await pumpTab(tester, isAdmin: isAdmin, size: size);

        expect(tester.takeException(), isNull);
        expect(find.text('Change password'), findsOneWidget);
        expect(
          find.ancestor(of: changePasswordRow, matching: find.byType(Tooltip)),
          findsWidgets,
        );
        await tester.ensureVisible(changePasswordRow);
        await tester.tap(changePasswordRow);
        expect(calls, ['change password']);
      });
    }
  }

  testWidgets('nobody signed in has no password to change', (tester) async {
    await pumpTab(tester, isAdmin: false, signedIn: false);

    expect(tester.takeException(), isNull);
    expect(changePasswordRow, findsNothing);
    expect(find.text('Not signed in'), findsOneWidget);
  });
}
