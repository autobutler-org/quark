import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _entries = [
  VaultEntryItem(id: 1, name: 'GitHub', subtitle: 'github.com'),
  VaultEntryItem(id: 2, name: 'bank'),
];

const _folders = [
  VaultFolderItem(id: 10, name: 'Work'),
  VaultFolderItem(id: 11, name: 'Home'),
];

void main() {
  VaultEntryList list({
    List<VaultEntryItem> entries = _entries,
    List<VaultFolderItem> folders = _folders,
    int? selectedFolderId,
    bool vaultIsEmpty = false,
    List<String>? log,
    bool withMenus = false,
  }) => VaultEntryList(
    entries: entries,
    folders: folders,
    selectedFolderId: selectedFolderId,
    vaultIsEmpty: vaultIsEmpty,
    onSearchChanged: (text) => log?.add('search:$text'),
    onFolderSelected: (id) => log?.add('folder:$id'),
    onDeleteFolder: (id) => log?.add('delete:$id'),
    onTapEntry: (id) => log?.add('tap:$id'),
    onEntryAction: withMenus
        ? (id, action) => log?.add('${action.name}:$id')
        : null,
  );

  testBothViewports('renders one row per entry, and the folders', (
    tester,
    size,
  ) async {
    await pumpAt(tester, list(), size: size);

    expect(find.byKey(const ValueKey('vault_entry_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('vault_entry_2')), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault_folder_all')), findsOneWidget);
    expect(find.byKey(const ValueKey('vault_folder_11')), findsOneWidget);
    expect(find.text('No passwords yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('says the vault is empty', (tester, size) async {
    await pumpAt(
      tester,
      list(entries: const [], folders: const [], vaultIsEmpty: true),
      size: size,
    );

    expect(find.text('No passwords yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault_folder_all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says a search matched nothing', (tester) async {
    await pumpAt(tester, list(entries: const []));

    expect(find.text('No matching entries'), findsOneWidget);
    expect(find.text('No passwords yet'), findsNothing);
  });

  testWidgets('reports the search, the folder and the entry', (tester) async {
    final log = <String>[];
    await pumpAt(tester, list(selectedFolderId: 10, log: log));

    await tester.enterText(find.byKey(const ValueKey('vault_search')), 'git');
    await tester.tap(find.byKey(const ValueKey('vault_folder_11')));
    await tester.tap(find.byKey(const ValueKey('vault_folder_all')));
    await tester.tap(find.byKey(const ValueKey('vault_entry_2')));
    await tester.pump();

    expect(log, ['search:git', 'folder:11', 'folder:null', 'tap:2']);
  });

  testBothViewports('offers to delete only a chosen folder, and reports it', (
    tester,
    size,
  ) async {
    await pumpAt(tester, list(), size: size);
    expect(find.byKey(const ValueKey('vault_folder_delete')), findsNothing);

    final log = <String>[];
    await pumpAt(tester, list(selectedFolderId: 11, log: log), size: size);
    expect(find.byTooltip('Delete folder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vault_folder_delete')));
    await tester.pump();

    expect(log, ['delete:11']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks the chosen folder', (tester) async {
    await pumpAt(tester, list(selectedFolderId: 10));

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('vault_folder_10')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('vault_folder_all')))
          .selected,
      isFalse,
    );
  });

  testBothViewports('the search field is a 48 px pill with 16 px text', (
    tester,
    size,
  ) async {
    await pumpAt(tester, list(), size: size);

    final field = find.byKey(const ValueKey('vault_search'));
    expect(tester.getSize(field).height, VaultEntryList.searchHeight);
    final text = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(text.style.fontSize, 16);
    final decorator = tester.widget<InputDecorator>(
      find.descendant(of: field, matching: find.byType(InputDecorator)),
    );
    final border = decorator.decoration.enabledBorder! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows have no menu unless asked for', (tester) async {
    await pumpAt(tester, list());

    expect(find.byKey(const ValueKey('vault_entry_menu_1')), findsNothing);
  });

  testBothViewports('each row\'s menu copies, edits and deletes', (
    tester,
    size,
  ) async {
    final log = <String>[];
    await pumpAt(tester, list(withMenus: true, log: log), size: size);

    for (final action in VaultEntryAction.values) {
      await tester.tap(find.byKey(const ValueKey('vault_entry_menu_1')));
      await tester.pumpAndSettle();
      expect(find.text('Copy password'), findsOneWidget);
      expect(find.text('Copy username'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('vault_entry_${action.name}_1')));
      await tester.pumpAndSettle();
    }

    expect(log, ['copyPassword:1', 'copyUsername:1', 'edit:1', 'delete:1']);
    expect(tester.takeException(), isNull);
  });
}
