import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/connection_sheet.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
    expect(find.text('Remote access settings'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
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

  test('labels every mode', () {
    for (final mode in ConnectionMode.values) {
      expect(ConnectionSheet.labelFor(mode), isNotEmpty);
    }
  });
}
