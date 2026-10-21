import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/recovery_phrase_controller.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/recovery_phrase/add_recovery_phrase_offer.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../controllers/vault_biometric_controller_test.dart' show FakeKeystore;
import '../support/fake_vault.dart';

const _password = 'correct horse battery staple';
const _phrase = 'apple bread cloud delta eagle flame';

/// #3530: an open vault whose key has no phrase wrap offers to add the
/// recovery phrase. A phrase the Quark refuses keeps the dialog open with
/// what was typed and changes nothing; the right one closes it and the offer
/// goes. Every state lays out on a phone and a desktop.
void main() {
  late AccountCrypto crypto;
  late FakeVault server;

  /// What the fake Quark was asked to add, as (password, phrase).
  late List<(String, String)> added;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(() {
    server = FakeVault();
    added = [];
  });

  /// Pumps the page at [size] over a vault set up under [_password], and an
  /// offer whose Quark says the vault key has no phrase wrap and takes only
  /// [_phrase].
  Future<VaultController> pump(WidgetTester tester, Size size) async {
    final seed = server.controller(crypto);
    await seed.load();
    await seed.setUp(_password);
    seed.dispose();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = server.controller(crypto);
    addTearDown(vault.dispose);
    final keystore = FakeKeystore();
    final biometric = VaultBiometricController(
      support: keystore.support,
      storedFingerprint: keystore.storedFingerprint,
      store: keystore.store,
      read: keystore.read,
      delete: keystore.delete,
      clearCache: () async {},
      account: () async => 'acct',
    );
    addTearDown(biometric.dispose);
    biometric.start(vault: vault, session: ValueNotifier('token'));
    var missing = (chat: false, vault: true);
    final phrase = RecoveryPhraseController(
      missing: () async => missing,
      addPhrase: ({required password, required phrase}) async {
        added.add((password, phrase));
        if (phrase != _phrase) {
          throw const MessageException(Errors.recoveryPhraseNotTheAccounts);
        }
        missing = (chat: false, vault: false);
      },
      account: () => 'grace',
    );
    addTearDown(phrase.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: VaultPage(
          controller: vault,
          biometric: biometric,
          recoveryPhrase: phrase,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vault;
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('vault_password_field')),
      _password,
    );
    await tester.tap(find.byKey(const ValueKey('vault_password_submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> typeAndSubmit(WidgetTester tester, String phrase) async {
    await tester.enterText(
      find.byKey(const ValueKey('add_recovery_phrase_phrase')),
      phrase,
    );
    await tester.enterText(
      find.byKey(const ValueKey('add_recovery_phrase_password')),
      _password,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('add_recovery_phrase_submit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add_recovery_phrase_submit')));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    final label = size.width < 400 ? 'narrow' : 'wide';

    testWidgets('offers the phrase only once the vault is open ($label)', (
      tester,
    ) async {
      final vault = await pump(tester, size);
      expect(find.byType(AddRecoveryPhraseOffer), findsNothing);

      await unlock(tester);

      expect(
        find.byKey(const ValueKey('recovery_phrase_offer')),
        findsOneWidget,
      );
      expect(find.text(AddRecoveryPhraseOffer.message), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Stops the idle timer before the test's timer check.
      vault.lock();
    });

    testWidgets('a phrase that is not the account\'s keeps the dialog open '
        'and the offer up; the right one adds it ($label)', (tester) async {
      final vault = await pump(tester, size);
      await unlock(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('recovery_phrase_offer_add')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recovery_phrase_offer_add')));
      await tester.pumpAndSettle();
      expect(find.byType(AddRecoveryPhraseDialog), findsOneWidget);

      await typeAndSubmit(tester, 'apple bread cloud delta eagle fame');
      expect(find.byType(AddRecoveryPhraseDialog), findsOneWidget);
      expect(find.text(Errors.recoveryPhraseNotTheAccounts), findsOneWidget);

      await typeAndSubmit(tester, _phrase);
      expect(find.byType(AddRecoveryPhraseDialog), findsNothing);
      expect(find.text(AddRecoveryPhraseOffer.added), findsOneWidget);
      expect(find.byType(AddRecoveryPhraseOffer), findsNothing);
      expect(added, [
        (_password, 'apple bread cloud delta eagle fame'),
        (_password, _phrase),
      ]);
      expect(tester.takeException(), isNull);
      // Stops the idle timer before the test's timer check.
      vault.lock();
    });

    testWidgets('not now puts the offer away ($label)', (tester) async {
      final vault = await pump(tester, size);
      await unlock(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('recovery_phrase_offer_dismiss')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('recovery_phrase_offer_dismiss')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AddRecoveryPhraseOffer), findsNothing);
      expect(added, isEmpty);
      vault.lock();
    });
  }
}
