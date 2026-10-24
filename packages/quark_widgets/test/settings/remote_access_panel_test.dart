import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The remote access panel (#2857): every state, who may change it, its
/// callbacks, and its keys.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget panel, {
    Size size = wideViewport,
  }) => pumpAt(tester, SingleChildScrollView(child: panel), size: size);

  testWidgets('shows a loader while loading', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(
        state: RemoteAccessState.off,
        isAdmin: true,
        isLoading: true,
      ),
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_access_set_up')), findsNothing);
  });

  testWidgets('shows the error with Retry', (tester) async {
    var retries = 0;
    await pump(
      tester,
      RemoteAccessPanel(
        state: RemoteAccessState.off,
        isAdmin: true,
        error: "Couldn't load remote access.",
        onRetry: () => retries++,
      ),
    );
    expect(find.text("Couldn't load remote access."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote_access_retry')));
    expect(retries, 1);
  });

  testBothViewports('offers an admin setup while off', (tester, size) async {
    var setUps = 0;
    await pump(
      tester,
      RemoteAccessPanel(
        state: RemoteAccessState.off,
        isAdmin: true,
        onSetUp: () => setUps++,
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Reach your Quark from anywhere'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote_access_status_off')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('remote_access_set_up')));
    expect(setUps, 1);
    expect(
      find.byKey(const ValueKey('remote_access_member_note')),
      findsNothing,
    );
  });

  testWidgets('tells a member who can turn it on', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(state: RemoteAccessState.off, isAdmin: false),
    );
    expect(
      find.byKey(const ValueKey('remote_access_member_note')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('remote_access_set_up')), findsNothing);
    // The panel is already on Settings, Network: sending the reader there
    // again reads like a wrong turn (#2901).
    final note = tester.widget<Text>(
      find.byKey(const ValueKey('remote_access_member_note')),
    );
    expect(note.data, isNot(contains('Settings')));
    expect(note.data, isNot(contains('Network')));
    expect(note.data, contains('Ask an admin'));
  });

  testWidgets('turning the switch off asks to turn off', (tester) async {
    var turnOffs = 0;
    await pump(
      tester,
      RemoteAccessPanel(
        state: RemoteAccessState.on,
        isAdmin: true,
        onTurnOff: () => turnOffs++,
      ),
    );
    expect(
      find.byKey(const ValueKey('remote_access_status_on')),
      findsOneWidget,
    );
    expect(find.text('Reachable away from home'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote_access_switch')));
    expect(turnOffs, 1);
  });

  testWidgets('gives a member a switch they cannot move', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(state: RemoteAccessState.on, isAdmin: false),
    );
    final toggle = tester.widget<Switch>(
      find.byKey(const ValueKey('remote_access_switch')),
    );
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);
  });

  testWidgets('shows connecting with a loader', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(
        state: RemoteAccessState.connecting,
        isAdmin: true,
      ),
    );
    expect(
      find.byKey(const ValueKey('remote_access_status_connecting')),
      findsOneWidget,
    );
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsOneWidget);
  });

  testBothViewports('a failure shows its steps, Try again and Turn off', (
    tester,
    size,
  ) async {
    final taps = <String>[];
    await pump(
      tester,
      RemoteAccessPanel(
        state: RemoteAccessState.failing,
        isAdmin: true,
        failure: 'It could not connect.',
        failureSteps: const ['First thing.', 'Second thing.'],
        onTryAgain: () => taps.add('again'),
        onTurnOff: () => taps.add('off'),
        onGetHelp: () => taps.add('help'),
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text("Couldn't connect"), findsOneWidget);
    expect(find.text('It could not connect.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Second thing.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote_access_try_again')));
    await tester.tap(find.byKey(const ValueKey('remote_access_turn_off')));
    await tester.tap(find.byKey(const ValueKey('remote_access_get_help')));
    expect(taps, ['again', 'off', 'help']);
  });

  testWidgets('a failure offers a member no buttons', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(
        state: RemoteAccessState.failing,
        isAdmin: false,
        failure: 'It could not connect.',
      ),
    );
    expect(find.byKey(const ValueKey('remote_access_try_again')), findsNothing);
    expect(find.byKey(const ValueKey('remote_access_turn_off')), findsNothing);
  });

  testWidgets('disables every control while working', (tester) async {
    await pump(
      tester,
      const RemoteAccessPanel(
        state: RemoteAccessState.failing,
        isAdmin: true,
        isWorking: true,
        failure: 'It could not connect.',
      ),
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('remote_access_switch')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('remote_access_turn_off')),
          )
          .onPressed,
      isNull,
    );
  });

  testLargeText('survives large text while failing', (tester, size) async {
    await pump(
      tester,
      const RemoteAccessPanel(
        state: RemoteAccessState.failing,
        isAdmin: true,
        failure: 'It could not connect.',
        failureSteps: ['Make sure your home internet is working.'],
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
