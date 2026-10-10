import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/unreachable_quark.dart';

/// #2740: Settings saves the user's own theme color and, for an admin, the
/// Quark's default, applying each at once and putting it back when the Quark
/// refuses.
void main() {
  final settings = AppSettings.instance;

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  late HttpOverrides? priorOverrides;
  final saves = <http.Request>[];

  /// What the Quark holds as the account's own settings; a save replaces it
  /// whole, as `PUT /settings/me` does.
  var mySettings = '{}';

  Future<void> reset() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.setSessionToken(null);
    settings.isAdmin.value = false;
  }

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    saves.clear();
    mySettings = '{}';
    await reset();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    await reset();
  });

  /// Opens Settings signed in on a Quark whose default is lime, answering
  /// every theme color save with [saveStatus] and everything else with a 404.
  Future<void> pumpSettings(
    WidgetTester tester, {
    bool isAdmin = false,
    int saveStatus = 200,
  }) async {
    sharedHttpClientFactory = () => MockClient((request) async {
      // A save of the user's own color reads their settings first, so it
      // can send the rest back unchanged (#2493).
      final isMine = request.url.path == '/api/v0/settings/me';
      if (request.method == 'GET' && isMine) {
        return http.Response(mySettings, 200);
      }
      if (request.method != 'PUT') return http.Response('', 404);
      saves.add(request);
      if (isMine && saveStatus == 200) mySettings = request.body;
      return http.Response(request.body, saveStatus);
    });
    await settings.addHost(
      HostEntry(name: 'Quark', hostAddress: 'https://quark.local'),
    );
    await settings.setSessionToken('a-session');
    settings.isAdmin.value = isAdmin;
    await settings.setQuarkThemeColor('lime');
    await settings.setUserThemeColor('');

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar at any viewport; ignore only that.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  const userPicker = ValueKey('settings_theme_color');
  const quarkPicker = ValueKey('settings_quark_theme_color');

  Finder within(ValueKey<String> picker, String key) =>
      find.descendant(of: find.byKey(picker), matching: find.byKey(Key(key)));

  QuarkThemeColorPicker picker(WidgetTester tester, ValueKey<String> key) =>
      tester.widget<QuarkThemeColorPicker>(find.byKey(key));

  testWidgets("a member follows the Quark's theme color and cannot set it", (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(picker(tester, userPicker).value, QuarkThemeColor.lime);
    expect(picker(tester, userPicker).usingDefault, isTrue);
    expect(find.byKey(quarkPicker), findsNothing);
  });

  testWidgets('picking a swatch saves it as the user and applies it', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(within(userPicker, 'theme_color_swatch_violet'));
    await tester.pump();

    expect(saves.single.url.path, '/api/v0/settings/me');
    expect(jsonDecode(saves.single.body), {'themeColor': 'violet'});
    expect(settings.themeColor.value, QuarkThemeColor.violet);
    expect(picker(tester, userPicker).value, QuarkThemeColor.violet);
    expect(picker(tester, userPicker).usingDefault, isFalse);

    await tester.tap(within(userPicker, 'theme_color_use_default'));
    await tester.pump();

    expect(jsonDecode(saves.last.body), {'themeColor': ''});
    expect(settings.themeColor.value, QuarkThemeColor.lime);
    expect(picker(tester, userPicker).usingDefault, isTrue);
  });

  testWidgets("an admin sets the Quark's default through the admin route", (
    tester,
  ) async {
    await pumpSettings(tester, isAdmin: true);

    expect(picker(tester, quarkPicker).value, QuarkThemeColor.lime);

    await tester.tap(within(quarkPicker, 'theme_color_swatch_pink'));
    await tester.pump();

    expect(saves.single.url.path, '/api/v0/settings/theme-color');
    expect(jsonDecode(saves.single.body), {'themeColor': 'pink'});
    expect(settings.quarkThemeColor.value, 'pink');
    // The admin follows the Quark, so their own color moves with it.
    expect(settings.themeColor.value, QuarkThemeColor.pink);
  });

  testWidgets('a refused save puts the previous theme color back and says so', (
    tester,
  ) async {
    await pumpSettings(tester, isAdmin: true, saveStatus: 400);

    await tester.tap(within(userPicker, 'theme_color_swatch_violet'));
    await tester.pump();
    await tester.pump();

    expect(settings.userThemeColor.value, '');
    expect(settings.themeColor.value, QuarkThemeColor.lime);
    expect(picker(tester, userPicker).usingDefault, isTrue);
    expect(
      find.textContaining("Couldn't save your theme color"),
      findsOneWidget,
    );

    await tester.tap(within(quarkPicker, 'theme_color_swatch_pink'));
    await tester.pump();
    await tester.pump();

    expect(settings.quarkThemeColor.value, 'lime');
    expect(picker(tester, quarkPicker).value, QuarkThemeColor.lime);
  });

  // #2773: with the previous value unknown, putting null back resolved to the
  // per-host cache, which the rejected pick had already overwritten.
  testWidgets('a refused save is undone when the previous value was unknown', (
    tester,
  ) async {
    await pumpSettings(tester, isAdmin: true, saveStatus: 400);
    // Neither fetch has answered: only the cached lime stands.
    await settings.setUserThemeColor(null);
    await settings.setQuarkThemeColor(null);
    await tester.pump();
    expect(settings.themeColor.value, QuarkThemeColor.lime);

    await tester.tap(within(userPicker, 'theme_color_swatch_violet'));
    await tester.pump();
    await tester.pump();

    expect(settings.userThemeColor.value, isNull);
    expect(settings.themeColor.value, QuarkThemeColor.lime);

    await tester.tap(within(quarkPicker, 'theme_color_swatch_pink'));
    await tester.pump();
    await tester.pump();

    expect(settings.quarkThemeColor.value, isNull);
    expect(settings.themeColor.value, QuarkThemeColor.lime);
  });

  // #2493: the switch and the color are saved through the same whole-object
  // write, so neither may drop the other.
  testWidgets('a theme color save keeps a notification type turned off', (
    tester,
  ) async {
    const dueToggle = ValueKey('notification_toggle_backup_due');
    await pumpSettings(tester, isAdmin: true);
    expect(tester.widget<SwitchListTile>(find.byKey(dueToggle)).value, isTrue);

    await tester.tap(find.byKey(dueToggle));
    await tester.pump(const Duration(milliseconds: 200));
    expect(jsonDecode(saves.last.body), {
      'disabledNotifications': ['backup_due'],
    });
    expect(tester.widget<SwitchListTile>(find.byKey(dueToggle)).value, isFalse);

    await tester.tap(within(userPicker, 'theme_color_swatch_violet'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(saves.last.url.path, '/api/v0/settings/me');
    expect(jsonDecode(saves.last.body), {
      'themeColor': 'violet',
      'disabledNotifications': ['backup_due'],
    });
  });

  testWidgets('a member has no notification switches', (tester) async {
    await pumpSettings(tester);
    expect(find.byType(SwitchListTile), findsWidgets);
    expect(
      find.byKey(const ValueKey('notification_toggle_backup_due')),
      findsNothing,
    );
    expect(find.text('Notifications'), findsNothing);
  });
}
