import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/vault_biometric.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../controllers/vault_biometric_controller_test.dart' show FakeKeystore;
import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';
const _account = 'acct_0123456789abcdef0123456789abcdef';

/// #3595: the vault page opens with Face ID, Touch ID or a fingerprint where
/// it is turned on, offers to turn it on once the vault is open, and keeps
/// the password one tap away. Every state lays out on a phone and a desktop.
void main() {
  late AccountCrypto crypto;
  late FakeVault server;
  late FakeKeystore keystore;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    keystore = FakeKeystore();
  });

  /// [server] with a vault under [_password] holding one login.
  Future<void> seed() async {
    final vault = server.controller(crypto);
    await vault.load();
    await vault.setUp(_password);
    await vault.save(
      const VaultItemData(
        kind: VaultItemKind.entry,
        name: 'Bank of Somewhere',
        url: 'https://bank.example/login',
        username: 'ada@example.com',
        password: 'hunter22-hunter22',
      ),
    );
    vault.dispose();
  }

  /// Pumps the page at [size] over a vault on [server] and a biometric
  /// controller on [keystore].
  Future<(VaultController, VaultBiometricController)> pump(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = server.controller(crypto);
    addTearDown(vault.dispose);
    final biometric = VaultBiometricController(
      support: keystore.support,
      storedFingerprint: keystore.storedFingerprint,
      store: keystore.store,
      read: keystore.read,
      delete: keystore.delete,
      clearCache: () async {},
      account: () async => _account,
    );
    addTearDown(biometric.dispose);
    biometric.start(vault: vault, session: ValueNotifier('token'));
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: VaultPage(controller: vault, biometric: biometric),
      ),
    );
    await tester.pumpAndSettle();
    return (vault, biometric);
  }

  /// Unlocks with the password, through the form.
  Future<void> unlockWithPassword(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('vault_password_field')),
      _password,
    );
    await tester.tap(find.byKey(const ValueKey('vault_password_submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Caches [vault]'s key in [keystore] as turning the setting on would.
  Future<void> turnOn(VaultController vault) => vault.cacheKey(
    (key, fingerprint) => keystore.store(_account, key, fingerprint, (
      title: '',
      reason: '',
      cancel: '',
    )),
  );

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    final label = size.width < 400 ? 'narrow' : 'wide';

    testWidgets('offers it after a password unlock, explains it before the '
        'switch, and turns it on ($label)', (tester) async {
      await seed();
      final (vault, biometric) = await pump(tester, size);
      expect(find.byKey(const ValueKey('vault_biometric_lock')), findsNothing);

      await unlockWithPassword(tester);
      expect(
        find.byKey(const ValueKey('vault_biometric_offer')),
        findsOneWidget,
      );
      expect(find.text('Unlock with Face ID?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('vault_biometric_offer_enable')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VaultBiometricSettingsDialog), findsOneWidget);
      expect(
        find.textContaining('Anyone who can pass Face ID'),
        findsOneWidget,
      );
      expect(keystore.entries, isEmpty);

      await tester.ensureVisible(
        find.byKey(const ValueKey('vault_biometric_switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vault_biometric_switch')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(biometric.enabled, isTrue);
      expect(keystore.entries, contains(_account));

      await tester.ensureVisible(
        find.byKey(const ValueKey('vault_biometric_settings_close')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('vault_biometric_settings_close')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vault_biometric_offer')), findsNothing);
      expect(
        find.byKey(const ValueKey('vault_biometric_settings')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // Stops the idle timer before the test's timer check.
      vault.lock();
    });

    testWidgets('the lock screen opens with Face ID and no password '
        '($label)', (tester) async {
      await seed();
      final (vault, _) = await pump(tester, size);
      await unlockWithPassword(tester);
      await turnOn(vault);
      await tester.runAsync(() => _biometricRefresh(tester));
      vault.lock();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vault_biometric_lock')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vault_password_field')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vault_biometric_unlock')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(vault.status, VaultStatus.unlocked);
      expect(find.text('Bank of Somewhere'), findsOneWidget);
      expect(tester.takeException(), isNull);
      vault.lock();
    });

    testWidgets('the password is one tap away, and an enrollment change '
        'falls back to it and says why ($label)', (tester) async {
      await seed();
      final (vault, _) = await pump(tester, size);
      await unlockWithPassword(tester);
      await turnOn(vault);
      await tester.runAsync(() => _biometricRefresh(tester));
      vault.lock();
      await tester.pumpAndSettle();

      keystore.nextPrompt = VaultBiometricFailure.invalidated;
      await tester.tap(find.byKey(const ValueKey('vault_biometric_unlock')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vault_biometric_lock')), findsNothing);
      expect(
        find.byKey(const ValueKey('vault_password_field')),
        findsOneWidget,
      );
      expect(find.text(Errors.vaultBiometricInvalidated), findsOneWidget);
      expect(keystore.entries, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('use password instead shows the form ($label)', (tester) async {
      await seed();
      final (vault, _) = await pump(tester, size);
      await unlockWithPassword(tester);
      await turnOn(vault);
      await tester.runAsync(() => _biometricRefresh(tester));
      vault.lock();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('vault_biometric_unlock_password')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vault_password_field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // Stops the idle timer before the test's timer check.
      vault.lock();
    });

    testWidgets('a device that cannot keep the key shows the page as it '
        'was ($label)', (tester) async {
      keystore.supported = (
        availability: VaultBiometricAvailability.unavailable,
        kind: VaultBiometricKind.biometrics,
      );
      await seed();
      final (vault, _) = await pump(tester, size);
      await unlockWithPassword(tester);

      expect(find.byKey(const ValueKey('vault_biometric_offer')), findsNothing);
      expect(
        find.byKey(const ValueKey('vault_biometric_settings')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      vault.lock();
    });
  }
}

/// Reads the keystore again through the page's controller, as a
/// pull-to-refresh would.
Future<void> _biometricRefresh(WidgetTester tester) async {
  final page = tester.widget<VaultPage>(find.byType(VaultPage));
  await page.biometric!.refresh();
}
