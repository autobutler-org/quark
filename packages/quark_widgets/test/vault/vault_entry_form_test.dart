import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  VaultEntryForm form({
    VaultEntryDraft initial = const VaultEntryDraft(),
    List<VaultFolderItem> folders = const [],
    bool isSaving = false,
    List<VaultEntryDraft>? saved,
    List<String>? generated,
  }) => VaultEntryForm(
    initial: initial,
    folders: folders,
    isSaving: isSaving,
    onGeneratePassword: () {
      generated?.add('gen');
      return 'Generated#1';
    },
    onSave: (draft) => saved?.add(draft),
  );

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('vault_entry_save')));

  testBothViewports('lays out every field without an exception', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      form(folders: const [VaultFolderItem(id: 1, name: 'Work')]),
      size: size,
    );

    for (final key in [
      'vault_entry_name',
      'vault_entry_url',
      'vault_entry_username',
      'vault_entry_password',
      'vault_entry_totp',
      'vault_entry_notes',
      'vault_entry_folder',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the folder field without folders, and save '
      'without a name', (tester) async {
    await pumpAt(tester, form());

    expect(find.byKey(const ValueKey('vault_entry_folder')), findsNothing);
    expect(saveButton(tester).onPressed, isNull);
  });

  testBothViewports('saves what was typed, once', (tester, size) async {
    final saved = <VaultEntryDraft>[];
    await pumpAt(
      tester,
      form(
        initial: const VaultEntryDraft(
          name: 'Old',
          username: 'grace',
          folderId: 1,
        ),
        folders: const [VaultFolderItem(id: 1, name: 'Work')],
        saved: saved,
      ),
      size: size,
    );

    await tester.enterText(
      find.byKey(const ValueKey('vault_entry_name')),
      '  GitHub ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('vault_entry_password')),
      'hunter22',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('vault_entry_save')));
    await tester.tap(find.byKey(const ValueKey('vault_entry_save')));
    await tester.pump();

    expect(saved, hasLength(1));
    expect(saved.single.name, 'GitHub');
    expect(saved.single.username, 'grace');
    expect(saved.single.password, 'hunter22');
    expect(saved.single.folderId, 1);
  });

  testBothViewports('generates a password into the field and shows it', (
    tester,
    size,
  ) async {
    final generated = <String>[];
    await pumpAt(tester, form(generated: generated), size: size);

    await tester.tap(find.byKey(const ValueKey('vault_entry_generate')));
    await tester.pump();

    expect(generated, ['gen']);
    expect(find.text('Generated#1'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('vault_entry_password')))
          .obscureText,
      isFalse,
    );
  });

  testWidgets('holds save still while saving', (tester) async {
    await pumpAt(
      tester,
      form(initial: const VaultEntryDraft(name: 'GitHub'), isSaving: true),
    );

    expect(saveButton(tester).onPressed, isNull);
    expect(find.byType(QuarkLoader), findsOneWidget);
  });
}
