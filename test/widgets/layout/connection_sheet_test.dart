import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/connection_sheet.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2857: tapping the app bar's connection indicator opens a sheet that
/// says how the app reaches its Quark and links to remote access settings.
void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required ConnectionMode mode,
    required Future<RemoteAccessStatus> Function() read,
    required ValueChanged<String> onNavigate,
    Size size = const Size(1280, 800),
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ConnectionSheetButton(
                mode: mode,
                onNavigate: onNavigate,
                readRemoteAccess: read,
              ),
            ],
          ),
        ),
      ),
    );
  }

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('opens the sheet and goes to settings (${size.width})', (
      tester,
    ) async {
      final routes = <String>[];
      await pumpButton(
        tester,
        mode: ConnectionMode.remote,
        read: () async =>
            const RemoteAccessStatus(enabled: true, connected: true),
        onNavigate: routes.add,
        size: size,
      );
      expect(find.byTooltip('Connected through remote access'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('connection_indicator')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('connection_sheet_status')),
          matching: find.text('Connected through remote access'),
        ),
        findsOneWidget,
      );
      expect(find.text('Remote access is on'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('connection_sheet_settings')));
      await tester.pumpAndSettle();
      expect(routes, ['/settings/network']);
      expect(
        find.byKey(const ValueKey('connection_sheet_settings')),
        findsNothing,
      );
    });
  }

  testWidgets('offline before this phone set up says to finish at home', (
    tester,
  ) async {
    setViewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ConnectionSheetButton(
                mode: ConnectionMode.offline,
                onNavigate: (_) {},
                readRemoteAccess: () async => throw Exception('unreachable'),
                thisPhoneOn: false,
                phoneStatus: Errors.finishRemoteAccessAtHome,
                offlineReason: Errors.finishRemoteAccessAtHome,
                onPause: (_) async {},
                onResume: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(Errors.quarkOutOfReach), findsNothing);
    // The header and the switch both say it.
    expect(find.text(Errors.finishRemoteAccessAtHome), findsNWidgets(2));
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('remote_access_on_this_phone')),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('offline says so in plain words, without a status', (
    tester,
  ) async {
    await pumpButton(
      tester,
      mode: ConnectionMode.offline,
      read: () async => throw Exception('unreachable'),
      onNavigate: (_) {},
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();

    expect(find.text(Errors.quarkOutOfReach), findsOneWidget);
    // A failed read says so, rather than the same words as one in flight
    // (#2904).
    expect(
      find.text(Errors.message(Exception(), 'load remote access status')),
      findsOneWidget,
    );
    expect(find.text('Checking remote access…'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('says it is checking while the status is read', (tester) async {
    final status = Completer<RemoteAccessStatus>();
    await pumpButton(
      tester,
      mode: ConnectionMode.local,
      read: () => status.future,
      onNavigate: (_) {},
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();
    expect(find.text('Checking remote access…'), findsOneWidget);

    status.complete(const RemoteAccessStatus(enabled: false));
    await tester.pumpAndSettle();
    expect(find.text('Checking remote access…'), findsNothing);
    expect(find.text('Remote access is off'), findsOneWidget);
  });

  testWidgets('shows a failing Quark as such', (tester) async {
    await pumpButton(
      tester,
      mode: ConnectionMode.local,
      read: () async =>
          const RemoteAccessStatus(enabled: true, error: 'tsnet: rejected'),
      onNavigate: (_) {},
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();

    expect(find.text("Remote access couldn't connect"), findsOneWidget);
    expect(find.textContaining('tsnet'), findsNothing);
  });

  // #3606: connected, a status read that got no answer is a failed check,
  // not "you're not connected", and the row offers a retry.
  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('a failed read while connected offers a retry '
        '(${size.width})', (tester) async {
      var reads = 0;
      var fail = true;
      await pumpButton(
        tester,
        mode: ConnectionMode.remote,
        read: () async {
          reads++;
          if (fail) throw http.ClientException('Connection closed');
          return const RemoteAccessStatus(enabled: true, connected: true);
        },
        onNavigate: (_) {},
        size: size,
      );
      await tester.tap(find.byKey(const ValueKey('connection_indicator')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reads, 2, reason: 'a read with no answer is tried once more');
      expect(find.text(quarkDisconnectedInline), findsNothing);
      expect(find.text("Couldn't check remote access."), findsOneWidget);

      fail = false;
      await tester.tap(find.byKey(const ValueKey('connection_sheet_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Remote access is on'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('connection_sheet_retry')),
        findsNothing,
      );
    });
  }

  testWidgets('a read that fails once and then answers shows the answer', (
    tester,
  ) async {
    var reads = 0;
    await pumpButton(
      tester,
      mode: ConnectionMode.remote,
      read: () async {
        if (reads++ == 0) throw http.ClientException('Connection closed');
        return const RemoteAccessStatus(enabled: true, connected: true);
      },
      onNavigate: (_) {},
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();

    expect(find.text('Remote access is on'), findsOneWidget);
    expect(find.text("Couldn't check remote access."), findsNothing);
  });

  testWidgets('reads again when the address changes', (tester) async {
    final address = ValueNotifier<String?>('https://quark.local');
    addTearDown(address.dispose);
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: ConnectionSheet(
            mode: ConnectionMode.remote,
            onOpenSettings: () {},
            addressChanges: address,
            address: () => address.value,
            readRemoteAccess: () async {
              if (fail) throw http.ClientException('Connection closed');
              return const RemoteAccessStatus(enabled: true, connected: true);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't check remote access."), findsOneWidget);

    fail = false;
    address.value = 'http://127.0.0.1:4242';
    await tester.pumpAndSettle();
    expect(find.text('Remote access is on'), findsOneWidget);
  });

  testWidgets('offline keeps the disconnected sentence', (tester) async {
    await pumpButton(
      tester,
      mode: ConnectionMode.offline,
      read: () async => throw http.ClientException('No route to host'),
      onNavigate: (_) {},
    );
    await tester.tap(find.byKey(const ValueKey('connection_indicator')));
    await tester.pumpAndSettle();

    expect(find.text(quarkDisconnectedInline), findsOneWidget);
  });

  test('labels every mode', () {
    for (final mode in ConnectionMode.values) {
      expect(ConnectionSheet.labelFor(mode), isNotEmpty);
    }
  });
}
