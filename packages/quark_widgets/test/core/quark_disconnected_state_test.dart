import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #1637: away from the Quark's network the app used to show whatever
/// connection error came back. These pin the replacement — the plain
/// statement, the troubleshooting steps, and the fact that neither shape ever
/// renders an exception.
///
/// Moved here with the widgets from the app's own test suite, where the state
/// used to read the host address out of `AppSettings` instead of taking it in.
void main() {
  group('QuarkDisconnectedView', () {
    testWidgets('states plainly that the app is not connected and lists '
        'every troubleshooting step', (tester) async {
      await pumpAt(tester, const QuarkDisconnectedView());

      expect(find.text(quarkDisconnectedHeadline), findsOneWidget);
      expect(find.text(quarkDisconnectedBody), findsOneWidget);
      for (final step in quarkTroubleshootingSteps) {
        expect(find.text(step), findsOneWidget);
      }
    });

    testWidgets('shows the address it could not reach', (tester) async {
      await pumpAt(
        tester,
        const QuarkDisconnectedView(hostAddress: 'https://quark.local'),
      );

      expect(find.text('https://quark.local'), findsOneWidget);
    });

    testWidgets('shows no address when the app names none', (tester) async {
      await pumpAt(
        tester,
        const QuarkDisconnectedView(hostAddress: ''),
        size: narrowViewport,
      );

      // Headline, body, and the three steps — no address line.
      expect(
        find.textContaining('http'),
        findsNothing,
        reason: 'an empty address must not render an empty line',
      );
    });

    testWidgets('offers no actions unless the caller supplies them', (
      tester,
    ) async {
      await pumpAt(tester, const QuarkDisconnectedView(), size: narrowViewport);

      // "Check the address" must not appear on a page that cannot go
      // anywhere useful — a button leading nowhere is worse than none.
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Check the address'), findsNothing);
    });

    testWidgets('retries through the callback the page supplied', (
      tester,
    ) async {
      var retries = 0;
      await pumpAt(tester, QuarkDisconnectedView(onRetry: () => retries++));

      await tester.tap(find.byKey(const ValueKey('disconnected_retry')));
      await tester.pumpAndSettle();

      expect(retries, 1);
    });

    testWidgets('routes to host management through its callback', (
      tester,
    ) async {
      var opened = 0;
      await pumpAt(
        tester,
        QuarkDisconnectedView(onManageHosts: () => opened++),
      );

      await tester.tap(find.byKey(const ValueKey('disconnected_manage_hosts')));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('renders the steps the caller chose', (tester) async {
      await pumpAt(
        tester,
        const QuarkDisconnectedView(steps: quarkTroubleshootingStepsInPlace),
        size: wideViewport,
      );

      expect(find.text('Check the Quark address.'), findsOneWidget);
    });
  });

  group('QuarkDisconnectedBanner', () {
    testWidgets('carries the same message in the compact shape', (
      tester,
    ) async {
      await pumpAt(tester, const QuarkDisconnectedBanner());

      expect(find.text(quarkDisconnectedHeadline), findsOneWidget);
      expect(find.text(quarkDisconnectedBody), findsOneWidget);
    });

    testWidgets('does not send the user to Settings they are already on', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const QuarkDisconnectedBanner(),
        size: narrowViewport,
      );

      expect(find.text('Check the Quark address.'), findsOneWidget);
      expect(find.text('Check the Quark address in Settings.'), findsNothing);
    });

    test('gives no directional guidance', () {
      // Login renders the host card above this banner and Settings renders
      // host management below it, so any on-screen direction is wrong on one
      // of them. Naming a destination is fine; pointing is not.
      for (final step in quarkTroubleshootingStepsInPlace) {
        expect(step, isNot(contains('below')));
        expect(step, isNot(contains('above')));
      }
    });

    testWidgets('retries through the callback the page supplied', (
      tester,
    ) async {
      var retries = 0;
      await pumpAt(tester, QuarkDisconnectedBanner(onRetry: () => retries++));

      await tester.tap(find.byKey(const ValueKey('disconnected_banner_retry')));
      await tester.pumpAndSettle();

      expect(retries, 1);
    });

    testWidgets('hides the retry button when there is nothing to retry', (
      tester,
    ) async {
      await pumpAt(tester, const QuarkDisconnectedBanner(), size: wideViewport);

      expect(find.text('Try again'), findsNothing);
    });
  });

  // #3778: remote access is built into Quark, so the checklist never names a
  // networking product, and the app retries by itself, so no step asks the
  // user to try again without a button that does it.
  group('troubleshooting steps', () {
    const vendorNames = ['tailscale', 'tsnet', 'headscale', 'wireguard'];

    for (final (name, steps) in [
      ('default', quarkTroubleshootingSteps),
      ('in place', quarkTroubleshootingStepsInPlace),
    ]) {
      test('$name steps name no vendor and ask for no retry', () {
        for (final step in steps) {
          for (final vendor in vendorNames) {
            expect(step.toLowerCase(), isNot(contains(vendor)));
          }
          expect(step.toLowerCase(), isNot(contains('try again')));
        }
      });
    }

    test('the default steps are the browser checklist', () {
      expect(quarkTroubleshootingSteps, [
        "Make sure you're on your home Wi-Fi.",
        'Make sure your Quark is switched on.',
        'Check the Quark address in Settings.',
      ]);
    });

    testBothViewports('the full-page view renders no vendor name', (
      tester,
      size,
    ) async {
      await pumpAt(tester, const QuarkDisconnectedView(), size: size);

      for (final vendor in vendorNames) {
        expect(
          find.textContaining(RegExp(vendor, caseSensitive: false)),
          findsNothing,
        );
      }
      for (final step in quarkTroubleshootingSteps) {
        expect(find.text(step), findsOneWidget);
      }
    });

    testBothViewports('the banner renders no vendor name', (
      tester,
      size,
    ) async {
      await pumpAt(tester, const QuarkDisconnectedBanner(), size: size);

      for (final vendor in vendorNames) {
        expect(
          find.textContaining(RegExp(vendor, caseSensitive: false)),
          findsNothing,
        );
      }
      for (final step in quarkTroubleshootingStepsInPlace) {
        expect(find.text(step), findsOneWidget);
      }
    });
  });
}
