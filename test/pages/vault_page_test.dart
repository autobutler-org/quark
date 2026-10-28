import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/models/vault_item.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_vault.dart';
import '../support/tap_target_guidelines.dart' show setViewport;
import '../support/text_scale.dart';

const _password = 'correct horse battery staple';

/// #3461: the vault page is a composition over [VaultController], which does
/// the crypto. Every state lays out on a phone and a desktop, at 200% text
/// too (#2606), and every control is labeled and big enough to hit (#2603,
/// #2605).
void main() {
  late AccountCrypto crypto;
  late FakeVault server;

  setUpAll(() async => crypto = await AccountCrypto.load());

  setUp(
    () =>
        server = FakeVault()
          ..loginAuthKey = fakeLoginAuthKey(crypto, _password),
  );

  /// Pumps the page over a controller on [server].
  Future<VaultController> pump(WidgetTester tester) async {
    final vault = server.controller(crypto);
    addTearDown(vault.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: VaultPage(controller: vault),
      ),
    );
    await tester.pumpAndSettle();
    return vault;
  }

  /// [server] with a vault under [_password] holding a login and a folder.
  Future<void> seed() async {
    final vault = server.controller(crypto);
    await vault.load();
    await vault.setUp(_password);
    final work = await vault.save(const VaultItemData.folder('Work'));
    await vault.save(
      VaultItemData(
        kind: VaultItemKind.entry,
        name: 'Bank of Somewhere',
        url: 'https://bank.example/login',
        username: 'ada@example.com',
        password: 'hunter22-hunter22',
        notes: 'Security question: the name of the first cat.',
        folderId: work,
      ),
    );
    vault.dispose();
  }

  Future<void> submitPassword(WidgetTester tester, String password) async {
    await tester.enterText(
      find.byKey(const ValueKey('vault_password_field')),
      password,
    );
    final submit = find.byKey(const ValueKey('vault_password_submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  /// Taps the bar action [key], opening the phone's "Manage" menu first when
  /// the row has collapsed into it (#3589).
  Future<void> tapBarAction(WidgetTester tester, String key) async {
    final menu = find.byKey(const ValueKey('app_bar_bottom_menu'));
    if (menu.evaluate().isNotEmpty) {
      await tester.tap(menu);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    group('at $size', () {
      void useSize(WidgetTester tester) {
        setViewport(tester, size);
      }

      testWidgets('a member sets up a vault with the login password', (
        tester,
      ) async {
        useSize(tester);
        final vault = await pump(tester);
        expect(find.text('Set up your vault'), findsOneWidget);
        // The Quark re-confirms the password, so it is asked for once.
        expect(
          find.byKey(const ValueKey('vault_password_confirm')),
          findsNothing,
        );

        await submitPassword(tester, 'not my password');
        expect(find.text(Errors.vaultNotLoginPassword), findsOneWidget);
        expect(find.text('Set up your vault'), findsOneWidget);
        expect(server.key, isNull);

        await submitPassword(tester, _password);
        expect(server.key, isNotNull);
        expect(find.text('No passwords yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Stops the idle timer before the test's timer check.
        vault.lock();
      });

      testWidgets('unlocks with the login password, not a wrong one', (
        tester,
      ) async {
        useSize(tester);
        await seed();
        final vault = await pump(tester);
        expect(find.text('Your vault is locked'), findsOneWidget);

        await submitPassword(tester, 'not it');
        expect(find.text(Errors.vaultWrongPassword), findsOneWidget);

        await submitPassword(tester, _password);
        expect(find.text('Bank of Somewhere'), findsOneWidget);
        expect(find.text('bank.example'), findsOneWidget);
        expect(find.byKey(const ValueKey('vault_folder_all')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(
          find.byKey(const ValueKey('vault_search')),
          'nothing like it',
        );
        await tester.pump();
        expect(find.text('No matching entries'), findsOneWidget);
        vault.lock();
      });

      testWidgets('adds, opens and deletes an entry, then locks', (
        tester,
      ) async {
        useSize(tester);
        await seed();
        final vault = await pump(tester);
        await submitPassword(tester, _password);

        await tapBarAction(tester, 'vault_new_entry');
        await tester.enterText(
          find.byKey(const ValueKey('vault_entry_name')),
          'Mail',
        );
        await tester.tap(find.byKey(const ValueKey('vault_entry_generate')));
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('vault_entry_save')),
        );
        await tester.tap(find.byKey(const ValueKey('vault_entry_save')));
        await tester.pumpAndSettle();
        expect(find.text('Mail'), findsOneWidget);
        expect(server.items, hasLength(3));
        expect(server.sent.last, isNot(contains('Mail')));

        final bank = vault.entries.firstWhere(
          (e) => e.data.name == 'Bank of Somewhere',
        );
        await tester.tap(find.byKey(ValueKey('vault_entry_${bank.id}')));
        await tester.pumpAndSettle();
        expect(find.text('ada@example.com'), findsOneWidget);
        expect(find.text('hunter22-hunter22'), findsNothing);
        expect(find.text('Work'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('vault_entry_delete')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('delete_vault_entry_confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Bank of Somewhere'), findsNothing);
        expect(server.items.containsKey(bank.id), isFalse);

        // Lock stays in the bar at every width, without scrolling (#3589).
        await tester.tap(find.byKey(const ValueKey('vault_lock')));
        await tester.pumpAndSettle();
        expect(find.text('Your vault is locked'), findsOneWidget);
        expect(vault.entries, isEmpty);
      });

      testWidgets('setup takes the recovery phrase for a phrase wrap', (
        tester,
      ) async {
        useSize(tester);
        final vault = await pump(tester);
        expect(
          find.textContaining('lets a recovery keep this vault'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('vault_password_phrase')),
          'apple-bread',
        );
        await submitPassword(tester, _password);

        expect(server.key!.byPhrase, isNotNull);
        expect(server.sent.single, isNot(contains('apple')));
        expect(find.text('No passwords yet'), findsOneWidget);
        vault.lock();
      });

      testWidgets('makes a folder, refuses a blank name, and deletes one '
          'leaving its entries in no folder', (tester) async {
        useSize(tester);
        await seed();
        final vault = await pump(tester);
        await submitPassword(tester, _password);

        await tapBarAction(tester, 'vault_new_folder');
        await tester.enterText(
          find.byKey(const ValueKey('name_dialog_field')),
          '   ',
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('name_dialog_submit')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('name_dialog_field')),
          'Home',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('name_dialog_submit')));
        await tester.pumpAndSettle();
        expect(find.byType(QuarkNameDialog), findsNothing);
        final home = vault.folders.firstWhere((f) => f.data.name == 'Home');
        expect(find.byKey(ValueKey('vault_folder_${home.id}')), findsOneWidget);
        expect(server.sent.last, isNot(contains('Home')));
        expect(tester.takeException(), isNull);

        final work = vault.folders.firstWhere((f) => f.data.name == 'Work');
        await tester.tap(find.byKey(ValueKey('vault_folder_${work.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('vault_folder_delete')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('delete_vault_folder_confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('vault_folder_${work.id}')), findsNothing);
        expect(server.items.containsKey(work.id), isFalse);
        // Back to all, with the entry that was in Work still listed.
        expect(find.text('Bank of Somewhere'), findsOneWidget);
        expect(vault.folderNameOf(vault.entries.single.data.folderId), '');
        vault.lock();
      });

      testWidgets('starting over deletes the vault after asking', (
        tester,
      ) async {
        useSize(tester);
        await seed();
        await pump(tester);

        await tester.tap(
          find.byKey(const ValueKey('vault_password_secondary')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vault_start_over_password_field')),
          _password,
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('vault_start_over_confirm')),
        );
        await tester.pumpAndSettle();

        expect(server.key, isNull);
        expect(find.text('Set up your vault'), findsOneWidget);
      });

      testWidgets('starting over with the wrong password deletes nothing '
          '(#3615)', (tester) async {
        useSize(tester);
        await seed();
        await pump(tester);

        await tester.tap(
          find.byKey(const ValueKey('vault_password_secondary')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vault_start_over_password_field')),
          'not the login password',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('vault_start_over_confirm')),
        );
        await tester.pumpAndSettle();

        expect(server.key, isNotNull);
        expect(server.items, isNotEmpty);
        expect(find.text(Errors.incorrectPassword), findsOneWidget);
        expect(find.byKey(const ValueKey('vault_unlock')), findsOneWidget);
      });

      testWidgets('a failed load offers a retry', (tester) async {
        useSize(tester);
        server.failKeyWith = 500;
        await pump(tester);

        expect(find.text('Retry'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  for (final (name, setUpVault) in <(String, Future<void> Function())>[
    ('setup', () async {}),
    ('unlock', seed),
  ]) {
    testLargeText('the $name view lays out and is accessible', (
      tester,
      _,
    ) async {
      await setUpVault();
      await pump(tester);

      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
    });
  }

  testLargeText('the entry list and an entry lay out and are accessible', (
    tester,
    _,
  ) async {
    await seed();
    final vault = await pump(tester);
    await submitPassword(tester, _password);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    final bank = vault.entries.single;
    await tester.tap(find.byKey(ValueKey('vault_entry_${bank.id}')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    await tester.tap(find.byKey(const ValueKey('vault_entry_edit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    // Locking leaves the entry, and stops the idle timer before the test's
    // timer check.
    vault.lock();
    await tester.pumpAndSettle();
    expect(find.text('Your vault is locked'), findsOneWidget);
  });

  testLargeText('the error view lays out', (tester, _) async {
    server.failKeyWith = 500;
    await pump(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });
}
