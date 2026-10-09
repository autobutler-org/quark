import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/setup_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/widgets/settings/hostname_section.dart';
import 'package:quark/widgets/setup/theme_step.dart';

import '../support/auth_salt.dart';

/// #2344: the last step of first-boot setup offers to name the Quark, once
/// there is an owner to ask as, and only on a Quark that can be renamed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};
  final settings = AppSettings.instance;
  final realChatKeysOnSignIn = chatKeysOnSignIn;

  /// What the fake Quark is called, and whether it can be renamed.
  var hostname = 'quark';
  var available = true;
  final hostnameRequests = <http.Request>[];

  setUpAll(() async {
    // Loaded once outside the fake clock, so setup can derive keys.
    await ChatCrypto.load();
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return stored[key];
            case 'write':
              stored[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              stored.remove(key);
              return null;
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    chatKeysOnSignIn = realChatKeysOnSignIn;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  setUp(() async {
    stored.clear();
    hostname = 'quark';
    available = true;
    hostnameRequests.clear();
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'https://quark.local'),
    );
    authStatusProbe = () async => const AuthStatus(setupComplete: false);
    authHttpClientFactory = () => AuthSaltClient(
      MockClient(
        (request) async => http.Response(jsonEncode({'token': 'owner'}), 200),
      ),
    );
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      if (request.url.path != '/api/v0/hostname') {
        return http.Response(jsonEncode({'error': ''}), 404);
      }
      hostnameRequests.add(request);
      if (request.method == 'PUT') {
        hostname = (jsonDecode(request.body) as Map)['hostname'] as String;
      }
      return http.Response(
        jsonEncode({
          'available': available,
          if (!available) 'reason': 'unsupported_os',
          'hostname': hostname,
        }),
        200,
      );
    });
  });

  tearDown(() async {
    await settings.setSessionToken(null);
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
    authHttpClientFactory = () => sharedHttpClient;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  /// Walks setup from the account form to the theme step.
  Future<void> reachThemeStep(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SetupPage(onSetupComplete: () {})),
    );
    await tester.pumpAndSettle();
    // Nobody is signed in yet, so the admin-only name is not asked for.
    expect(find.byType(HostnameSection), findsNothing);
    expect(hostnameRequests, isEmpty);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'owner');
    await tester.enterText(fields.at(1), 'correct-horse-battery');
    await tester.enterText(fields.at(2), 'correct-horse-battery');
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Create account'),
    );
    await pumpWhileDeriving(tester);
    await tester.pumpAndSettle();
    expect(hostnameRequests, isEmpty);

    await tapVisible(tester, find.byType(CheckboxListTile));
    await tester.pump();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeStep), findsOneWidget);
  }

  final field = find.byKey(const ValueKey('hostname_field'));
  final save = find.byKey(const ValueKey('hostname_save'));

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('the theme step names the Quark and follows it ($name)', (
      tester,
    ) async {
      await reachThemeStep(tester, size);

      expect(tester.takeException(), isNull);
      expect(find.text('Name this Quark'), findsOneWidget);
      expect(tester.widget<TextFormField>(field).controller?.text, 'quark');
      expect(hostnameRequests.single.headers['Authorization'], 'Bearer owner');

      await tester.ensureVisible(field);
      await tester.enterText(field, 'kitchen');
      await tester.pump();
      await tapVisible(tester, save);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(hostnameRequests.last.method, 'PUT');
      expect(find.text('This Quark is now at kitchen.local.'), findsOneWidget);
      // The saved Quark moved with it, still signed in, and setup goes on.
      expect(settings.hosts.single.name, 'Home');
      expect(settings.activeHost, 'https://kitchen.local');
      expect(settings.sessionToken, 'owner');
      expect(settings.username, 'owner');
      expect(find.byType(ThemeStep), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Get started'), findsOneWidget);
    });

    testWidgets("a Quark that can't be renamed has no name field ($name)", (
      tester,
    ) async {
      available = false;
      await reachThemeStep(tester, size);

      expect(tester.takeException(), isNull);
      expect(hostnameRequests.single.method, 'GET');
      expect(find.byType(HostnameSection), findsOneWidget);
      expect(find.text('Name this Quark'), findsNothing);
      expect(field, findsNothing);
      expect(find.widgetWithText(FilledButton, 'Get started'), findsOneWidget);
    });
  }
}
