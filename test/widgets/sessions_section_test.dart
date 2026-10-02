import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/sessions_controller.dart';
import 'package:quark/models/auth_session.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/sessions_section.dart';

/// #1663: the Sessions card marks the session in use, asks before signing
/// anything out, and leaves the page once the session in use is gone.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final current = AuthSession(
    id: 'current',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    lastUsedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    current: true,
  );
  final other = AuthSession(
    id: 'other',
    createdAt: DateTime.now().subtract(const Duration(days: 9)),
    lastUsedAt: DateTime.now().subtract(const Duration(hours: 2)),
    current: false,
  );

  final revokeOthers = find.byKey(const ValueKey('sessions_revoke_others'));

  Future<List<String>> pumpSection(
    WidgetTester tester,
    Size size, {
    bool failList = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calls = <String>[];
    var sessions = [current, other];
    final controller = SessionsController(
      list: () async {
        if (failList) throw const ApiException(500);
        return sessions;
      },
      revoke: (id) async {
        calls.add('revoke $id');
        sessions = [current];
      },
      revokeOthers: () async {
        calls.add('revoke others');
        sessions = [current];
      },
      logout: () async => calls.add('logout'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionsSection(
              controller: controller,
              onSignedOut: () => calls.add('signed out'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('lists the sessions and marks the current one ($label)', (
      tester,
    ) async {
      await pumpSection(tester, size);
      expect(find.text('This session'), findsOneWidget);
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Signed in 3d ago · last used 5m ago'), findsOneWidget);
      expect(find.text('Signed in 9d ago · last used 2h ago'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('asks before signing another session out ($label)', (
      tester,
    ) async {
      final calls = await pumpSection(tester, size);
      final revoke = find.byKey(const ValueKey('session_revoke_other'));

      await tester.tap(revoke);
      await tester.pumpAndSettle();
      expect(find.text('Sign out that session?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(revoke);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(calls, ['revoke other']);
      expect(find.byKey(const ValueKey('session_tile_other')), findsNothing);
    });

    testWidgets('signing out everywhere else keeps this session ($label)', (
      tester,
    ) async {
      final calls = await pumpSection(tester, size);

      await tester.tap(revokeOthers);
      await tester.pumpAndSettle();
      expect(find.text('Sign out everywhere else?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(calls, ['revoke others']);
      expect(find.text('This session'), findsOneWidget);
      expect(find.byKey(const ValueKey('session_tile_other')), findsNothing);
      expect(tester.widget<TextButton>(revokeOthers).onPressed, isNull);
    });

    testWidgets('signing out this session logs out and leaves ($label)', (
      tester,
    ) async {
      final calls = await pumpSection(tester, size);

      await tester.tap(find.byKey(const ValueKey('session_revoke_current')));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(calls, ['logout', 'signed out']);
    });

    testWidgets('a failed load shows the error copy ($label)', (tester) async {
      await pumpSection(tester, size, failList: true);
      expect(
        find.text(
          Errors.message(const ApiException(500), 'load your sessions'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(revokeOthers).onPressed, isNull);
    });
  }
}
