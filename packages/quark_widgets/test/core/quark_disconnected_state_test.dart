// cspell:words kwallet libtailscale
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

    testWidgets('a reason set on the view replaces the checklist', (
      tester,
    ) async {
      QuarkDisconnectedView.reason = QuarkUnreachableReason.notSetUp;
      addTearDown(() => QuarkDisconnectedView.reason = null);
      await pumpAt(tester, const QuarkDisconnectedView());

      expect(find.text('Finish setting up at home.'), findsOneWidget);
      expect(find.text(quarkDisconnectedBody), findsNothing);
      expect(find.text(quarkTroubleshootingSteps.first), findsNothing);
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

    testWidgets('a reason set for pages that already build it replaces '
        'the checklist', (tester) async {
      QuarkDisconnectedView.reason = QuarkUnreachableReason.notSetUp;
      addTearDown(() => QuarkDisconnectedView.reason = null);
      await pumpAt(tester, const QuarkDisconnectedBanner());

      expect(find.text('Finish setting up at home.'), findsOneWidget);
      expect(find.text(quarkDisconnectedBody), findsNothing);
      expect(find.text(quarkTroubleshootingStepsInPlace.first), findsNothing);
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

  // #3778: the checklist used to name a networking vendor and ask for a
  // manual network check. A browser gets three plain steps. A phone shows
  // the reason it already knows (#3776) and no checklist.
  test('the steps name no vendor and never say to try again', () {
    for (final step in [
      ...quarkTroubleshootingSteps,
      ...quarkTroubleshootingStepsInPlace,
    ]) {
      expect(step, isNot(contains(_vendorName)));
      expect(step.toLowerCase(), isNot(contains('try again')));
    }
    expect(quarkTroubleshootingSteps, [
      "Make sure you're on your home Wi‑Fi.",
      'Make sure your Quark is switched on.',
      'Check the Quark address in Settings.',
    ]);
    expect(quarkTroubleshootingStepsInPlace, [
      "Make sure you're on your home Wi‑Fi.",
      'Make sure your Quark is switched on.',
      'Check the Quark address.',
    ]);
  });

  testBothViewports(
    'the checklist names no vendor and a phone shows its reason',
    (tester, size) async {
      await pumpAt(tester, const QuarkDisconnectedView(), size: size);
      expect(tester.takeException(), isNull);
      for (final step in quarkTroubleshootingSteps) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.textContaining(_vendorName), findsNothing);

      await pumpAt(tester, const QuarkDisconnectedBanner(), size: size);
      expect(tester.takeException(), isNull);
      for (final step in quarkTroubleshootingStepsInPlace) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.text('Check the Quark address in Settings.'), findsNothing);
      expect(find.textContaining(_vendorName), findsNothing);

      for (final (reason, headline, body) in _phoneReasons) {
        expect(reason.headline, headline);
        expect(reason.body, body);

        await pumpAt(
          tester,
          QuarkDisconnectedView(unreachableReason: reason),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(headline), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(find.text(quarkDisconnectedHeadline), findsNothing);
        expect(find.text(quarkTroubleshootingSteps.first), findsNothing);
        expect(find.textContaining(_vendorName), findsNothing);

        await pumpAt(
          tester,
          QuarkDisconnectedBanner(unreachableReason: reason),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(headline), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(find.text(quarkTroubleshootingStepsInPlace.first), findsNothing);
        expect(find.textContaining(_vendorName), findsNothing);
      }
    },
  );

  // The app bar host assigns [QuarkDisconnectedView.reason] while it
  // rebuilds and passes the same page back down. A screen already showing
  // the browser checklist has to swap in the phone's reason without the
  // page around it building again.
  testBothViewports(
    'a reason set after the screen is up replaces the checklist',
    (tester, size) async {
      final published = ValueNotifier<QuarkUnreachableReason?>(null);
      final pageBuilds = <int>[0];
      addTearDown(() => QuarkDisconnectedView.reason = null);

      await pumpAt(
        tester,
        ValueListenableBuilder<QuarkUnreachableReason?>(
          valueListenable: published,
          builder: (context, value, child) {
            QuarkDisconnectedView.reason = value;
            return child!;
          },
          child: Column(
            children: [
              _StaysMounted(builds: pageBuilds),
              const QuarkDisconnectedBanner(),
              const Expanded(child: QuarkDisconnectedView()),
            ],
          ),
        ),
        size: size,
      );

      expect(find.text(quarkTroubleshootingSteps.first), findsNWidgets(2));
      expect(find.text('Check the Quark address in Settings.'), findsOneWidget);
      expect(find.text('Check the Quark address.'), findsOneWidget);
      expect(pageBuilds.single, 1);
      expect(tester.takeException(), isNull);

      for (final (reason, headline, body) in _phoneReasons) {
        published.value = reason;
        await tester.pump();

        expect(find.text(headline), findsNWidgets(2));
        expect(find.text(body), findsNWidgets(2));
        expect(find.text(quarkDisconnectedHeadline), findsNothing);
        expect(find.text(quarkTroubleshootingSteps.first), findsNothing);
        expect(find.textContaining(_vendorName), findsNothing);
        expect(pageBuilds.single, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

/// Counts its own builds. The unreachable screen sits beside it, and a
/// reason change must leave the count alone.
class _StaysMounted extends StatelessWidget {
  const _StaysMounted({required this.builds});

  /// Incremented on each build. A one-element list so the test can read it.
  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds[0] += 1;
    return const SizedBox.shrink();
  }
}

/// Vendor and library names that must not appear in the unreachable copy.
final RegExp _vendorName = RegExp(
  'tailscale|headscale|tsnet|wireguard|kwallet|gnome keyring|'
  'gnome-keyring|libtailscale|tailnet',
  caseSensitive: false,
);

/// The away-screen sentences from #3776, one per reason the phone can know.
const List<(QuarkUnreachableReason, String, String)> _phoneReasons = [
  (
    QuarkUnreachableReason.notSetUp,
    'Finish setting up at home.',
    "This phone isn't set up for remote access yet. Next time you're on "
        'your home Wi‑Fi, open Quark. It sets itself up in a few seconds, '
        'and then works away from home.',
  ),
  (
    QuarkUnreachableReason.paused,
    'Remote access is paused.',
    'You paused it on this phone.',
  ),
  (
    QuarkUnreachableReason.notAnswering,
    "Your Quark isn't answering.",
    'It may be switched off, or your home internet may be down. '
        "We'll reconnect by ourselves.",
  ),
  (
    QuarkUnreachableReason.noInternet,
    'No internet on this phone.',
    "Quark will reconnect as soon as you're back online.",
  ),
  (
    QuarkUnreachableReason.needsSignIn,
    'This Wi‑Fi needs a sign-in first.',
    "Sign in or accept the network's terms in your browser, or switch to "
        'mobile data. Quark reconnects by itself.',
  ),
];
