import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/text_scale.dart';

/// #2068: with the keyboard open on a phone, focusing a field scrolled only
/// that field into view, so Sign in, Forgot password and the setup link sat
/// below the keyboard where nobody could see them.
void main() {
  final settings = AppSettings.instance;

  // A Pixel 6 in logical pixels, and roughly the height its keyboard takes.
  const screen = Size(412, 915);
  const keyboard = 330.0;

  setUp(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://localhost:8094'),
    );
    // An unclaimed Quark, so the setup link — the last thing on the form —
    // is showing.
    authStatusProbe = () async => const AuthStatus(setupComplete: false);
  });

  tearDown(() async {
    authStatusProbe = AuthService.checkStatus;
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          onLoginSuccess: () {},
          checkStatus: () async => const AuthStatus(setupComplete: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Focuses the field labeled [label] and opens the keyboard over it.
  Future<void> focusWithKeyboard(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(TextFormField, label));
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();
  }

  void expectAboveKeyboard(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height - keyboard),
      reason: '$finder ends at ${rect.bottom}, under the keyboard',
    );
    expect(rect.top, greaterThanOrEqualTo(0));
  }

  final signIn = find.byKey(const ValueKey('login_submit'));
  final forgot = find.text('Forgot password?');
  final setUpLink = find.byKey(const ValueKey('login_set_up_quark'));

  for (final field in ['Username', 'Password']) {
    testWidgets('focusing $field keeps every action above the keyboard', (
      tester,
    ) async {
      await pumpLogin(tester);

      await focusWithKeyboard(tester, field);

      expectAboveKeyboard(tester, find.widgetWithText(TextFormField, field));
      expectAboveKeyboard(tester, signIn);
      expectAboveKeyboard(tester, forgot);
      expectAboveKeyboard(tester, setUpLink);
    });
  }

  testWidgets('the actions stay above the keyboard with the host list open', (
    tester,
  ) async {
    await pumpLogin(tester);
    await focusWithKeyboard(tester, 'Password');

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    // The open list pushes the form down; the user scrolls until the
    // password is just back in sight and taps it again.
    final password = find.widgetWithText(TextFormField, 'Password');
    unawaited(
      Scrollable.ensureVisible(
        tester.element(password),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(password);
    await tester.pumpAndSettle();

    expectAboveKeyboard(tester, password);
    expectAboveKeyboard(tester, signIn);
  });
  // #2606, #2603, #2605: the form, with the host list open or shut, survives
  // 200% text on a phone and a desktop, and every control on it is labeled
  // and big enough to hit.
  for (final hostsOpen in [false, true]) {
    testLargeText(
      'the form lays out with the host list ${hostsOpen ? 'open' : 'shut'}',
      (tester, _) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
            home: LoginPage(
              onLoginSuccess: () {},
              notice: 'Your session ended. Sign in again to carry on.',
              checkStatus: () async => const AuthStatus(setupComplete: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (hostsOpen) {
          await tester.ensureVisible(find.text('Change'));
          await tester.tap(find.text('Change'));
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        await expectTapTargetGuidelines(tester);
      },
    );
  }
}
