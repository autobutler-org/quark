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
import 'package:quark/widgets/setup/recovery_phrase_step.dart';
import 'package:quark/widgets/setup/theme_step.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/auth_salt.dart';

/// #2026: first-boot setup is three steps, and every one of them says which
/// it is and how many there are, so the user can see the end from the start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final stored = <String, String>{};
  final settings = AppSettings.instance;
  final realChatKeysOnSignIn = chatKeysOnSignIn;

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
    await clearHosts();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://quark.local'),
    );
    authStatusProbe = () async => const AuthStatus(setupComplete: false);
    authHttpClientFactory = () => AuthSaltClient(
      MockClient(
        (request) async => http.Response(jsonEncode({'token': 'owner'}), 200),
      ),
    );
  });

  tearDown(() async {
    await settings.setSessionToken(null);
    await clearHosts();
    authStatusProbe = AuthService.checkStatus;
    authHttpClientFactory = () => sharedHttpClient;
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('every setup step names its place in the three ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: SetupPage(onSetupComplete: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuarkStepIndicator), findsOneWidget);
      expect(find.text('Step 1 of 3 — Create account'), findsOneWidget);

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

      expect(find.byType(RecoveryPhraseStep), findsOneWidget);
      expect(find.byType(QuarkStepIndicator), findsOneWidget);
      expect(find.text('Step 2 of 3 — Recovery phrase'), findsOneWidget);

      await tapVisible(tester, find.byType(CheckboxListTile));
      await tester.pump();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(ThemeStep), findsOneWidget);
      expect(find.byType(QuarkStepIndicator), findsOneWidget);
      expect(find.text('Step 3 of 3 — Theme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
