import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The sheet behind the app bar's connection indicator (#2857): the mode in
/// words, and a link to the Quark's remote access settings.
void main() {
  testBothViewports('shows the mode and the Quark\'s remote access', (
    tester,
    size,
  ) async {
    var opens = 0;
    await pumpAt(
      tester,
      ConnectionStatusView(
        mode: ConnectionMode.remote,
        label: 'Connected through remote access',
        detail: 'You are away from home.',
        remoteAccess: RemoteAccessState.on,
        onOpenSettings: () => opens++,
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Connected through remote access'), findsOneWidget);
    expect(find.text('You are away from home.'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.cloud_done_outlined), findsOneWidget);
    expect(find.text('Remote access is on'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('connection_sheet_settings')));
    expect(opens, 1);
  });

  for (final (state, words) in [
    (null, 'Remote access settings'),
    (RemoteAccessState.off, 'Remote access is off'),
    (RemoteAccessState.connecting, 'Remote access is connecting'),
    (RemoteAccessState.failing, "Remote access couldn't connect"),
  ]) {
    testWidgets('says remote access is ${state?.name ?? 'unknown'}', (
      tester,
    ) async {
      await pumpAt(
        tester,
        ConnectionStatusView(
          mode: ConnectionMode.local,
          label: 'Home',
          detail: 'Detail.',
          remoteAccess: state,
          onOpenSettings: () {},
        ),
      );
      expect(find.text(words), findsOneWidget);
    });
  }

  // Reading the state and failing to read it are different answers, and
  // the row says which (#2904).
  testBothViewports('says remote access is being checked', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      ConnectionStatusView(
        mode: ConnectionMode.local,
        label: 'Home',
        detail: 'Detail.',
        isCheckingRemoteAccess: true,
        onOpenSettings: () {},
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Checking remote access…'), findsOneWidget);
    expect(find.text('Remote access settings'), findsNothing);
  });

  testBothViewports('says why remote access could not be read', (
    tester,
    size,
  ) async {
    var opens = 0;
    await pumpAt(
      tester,
      ConnectionStatusView(
        mode: ConnectionMode.local,
        label: 'Home',
        detail: 'Detail.',
        remoteAccessError: "Couldn't load remote access status.",
        onOpenSettings: () => opens++,
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.text("Couldn't load remote access status."), findsOneWidget);
    expect(find.text('Remote access settings'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('connection_sheet_settings')));
    expect(opens, 1);
  });

  testWidgets('hides the settings row without onOpenSettings', (tester) async {
    await pumpAt(
      tester,
      const ConnectionStatusView(
        mode: ConnectionMode.offline,
        label: 'Not reachable',
        detail: 'Detail.',
      ),
    );
    expect(
      find.byKey(const ValueKey('connection_sheet_settings')),
      findsNothing,
    );
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpInSheet(
      tester,
      ConnectionStatusView(
        mode: ConnectionMode.remote,
        label: 'Connected through remote access',
        detail: 'You are away from home, so the app goes the long way round.',
        remoteAccess: RemoteAccessState.failing,
        onOpenSettings: () {},
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
