import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/pages/recover_page.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/widgets/login/back_to_sign_in.dart';
import 'package:quark/widgets/setup/recovery_phrase_step.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';

/// #2430: recovering an account the Quark marks `legacyRecovery` sends its
/// old phrase once and gives it a new one the app made. The page shows that
/// phrase, holds Back on it, and leaves for sign-in only once it has been
/// acknowledged, since it is never shown again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final settings = AppSettings.instance;
  final bodies = <Map<String, dynamic>>[];

  setUpAll(() async {
    // Loaded once outside the fake clock, so the recovery can derive keys.
    await ChatCrypto.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    bodies.clear();
    // A clean slate each run: the app remembers a host's recovery key even
    // after the host is removed.
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://quark.local'),
    );
    chatKeysOnSignIn =
        ({
          required password,
          phraseWrapKey,
          required sessionToken,
          authSalt,
        }) async => null;
    chatKeysForRecovery =
        ({
          required username,
          required recoveryPhrase,
          recoveryKeys,
          newPhraseWrapKey,
          required newPassword,
          required authSalt,
        }) async => WrappedChatKeys(
          publicKeys: ChatPublicKeys(
            boxPublicKey: Uint8List(32),
            signPublicKey: Uint8List(32),
          ),
          byPassword: WrappedSecret(wrapped: Uint8List(104), salt: authSalt),
          byPhrase: null,
          kdfParams: KdfParams.standard.split,
        );
    authHttpClientFactory = () => AuthSaltClient(
      MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'token': 'new-token'}), 200);
      }),
      legacyRecovery: true,
    );
  });

  tearDown(() async {
    await settings.setSessionToken(null);
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    chatKeysForRecovery = ChatKeysController.instance.keysForRecovery;
    authHttpClientFactory = () => sharedHttpClient;
  });

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('a legacy recovery shows the new phrase until it is '
        'acknowledged at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var finished = 0;

      await tester.pumpWidget(
        MaterialApp(home: RecoverPage(onRecoverSuccess: () => finished++)),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'grace');
      await tester.enterText(fields.at(1), 'old-quark-phrase');
      await tester.enterText(fields.at(2), 'brand-new-password');
      await tester.enterText(fields.at(3), 'brand-new-password');
      await tester.ensureVisible(find.text('Reset password'));
      await tester.tap(find.text('Reset password'));
      await pumpWhileDeriving(tester);
      await tester.pumpAndSettle();

      final body = bodies.single;
      expect(body['recoveryPhrase'], 'old-quark-phrase');
      expect(body, contains('newRecoveryKey'));
      final step = tester.widget<RecoveryPhraseStep>(
        find.byType(RecoveryPhraseStep),
      );
      expect(step.phrase.split('-'), hasLength(6));
      expect(
        tester.widget<BackToSignIn>(find.byType(BackToSignIn)).enabled,
        isFalse,
      );
      expect(finished, 0);

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
