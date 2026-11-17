import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../models/vault_entry_item.dart';
import '../theme/quark_tokens.dart';
import 'vault_entry_list/vault_entry_tile.dart';
import 'vault_entry_list/vault_folder_chips.dart';

/// An unlocked vault's entries: a rounded search field first, a folder filter
/// when there are folders, and one row per entry (#4234).
///
/// Filtering is the caller's: [entries] is already what the search and the
/// folder leave, and the box and chips only report what was typed or chosen.
/// [vaultIsEmpty] tells an empty vault apart from a search that matched
/// nothing.
///
/// Key prefixes: `vault_search` on the search box, `vault_entry_<id>` on each
/// row, `vault_folder_all` and `vault_folder_<id>` on the folder chips, and
/// `vault_folder_delete` on the chosen folder's delete button. With
/// [onEntryAction] set each row has a ⋮ menu, keyed `vault_entry_menu_<id>`,
/// whose rows are `vault_entry_<action>_<id>` for each [VaultEntryAction].
///
/// The list leaves room at its end for a page's floating `+` button.
///
/// ```dart
/// VaultEntryList(
///   entries: controller.visibleRows,
///   folders: controller.folderOptions,
///   selectedFolderId: controller.folderId,
///   vaultIsEmpty: controller.entries.isEmpty,
///   onSearchChanged: controller.search,
///   onFolderSelected: controller.filterFolder,
///   onDeleteFolder: confirmDeleteFolder,
///   onTapEntry: openEntry,
///   onEntryAction: runEntryAction,
/// );
/// ```
class VaultEntryList extends StatelessWidget {
  /// Creates the list of [entries].
  const VaultEntryList({
    required this.entries,
    required this.onSearchChanged,
    required this.onTapEntry,
    this.folders = const [],
    this.selectedFolderId,
    this.onFolderSelected,
    this.onDeleteFolder,
    this.vaultIsEmpty = false,
    this.initialQuery = '',
    this.onEntryAction,
    super.key,
  });

  /// The entries to list, in order, already filtered.
  final List<VaultEntryItem> entries;

  /// Called with the search box's text as it changes.
  final ValueChanged<String> onSearchChanged;

  /// Called with the id of the entry tapped.
  final ValueChanged<int> onTapEntry;

  /// The folders to filter by. Empty hides the filter.
  final List<VaultFolderItem> folders;

  /// The folder filtered to, or null for all.
  final int? selectedFolderId;

  /// Called with the folder chosen, or null for all. Null hides the filter.
  final ValueChanged<int?>? onFolderSelected;

  /// Called with the chosen folder's id when its delete button is tapped.
  /// Null hides the button; deleting, and asking first, are the caller's.
  final ValueChanged<int>? onDeleteFolder;

  /// Whether the vault holds no entries at all, as opposed to none matching.
  final bool vaultIsEmpty;

  /// What the search box starts with.
  final String initialQuery;

  /// Called with an entry's id and the row its menu chose: copy the password
  /// or username, edit, or delete. Null hides the menus.
  final void Function(int id, VaultEntryAction action)? onEntryAction;

  /// The search field's height: the 48 px touch target the app's
  /// accessibility checks hold every control to.
  static const double searchHeight = 48;

  /// Space left under the last row so a floating `+` button never covers it.
  static const double floatingButtonClearance = 88;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onFolderSelected = this.onFolderSelected;
    final onEntryAction = this.onEntryAction;
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(searchHeight / 2),
      borderSide: BorderSide(color: tokens.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacingMd,
            tokens.spacingSm,
            tokens.spacingMd,
            tokens.spacingSm,
          ),
          child: SizedBox(
            height: searchHeight,
            child: TextFormField(
              key: const ValueKey('vault_search'),
              initialValue: initialQuery,
              style: const TextStyle(fontSize: 16),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'Search the vault',
                prefixIcon: const Icon(QuarkIcons.search),
                border: pill,
                enabledBorder: pill,
                focusedBorder: pill.copyWith(
                  borderSide: BorderSide(color: tokens.focus, width: 2),
                ),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: tokens.spacingMd,
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),
        if (folders.isNotEmpty && onFolderSelected != null)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacingSm),
            child: VaultFolderChips(
              folders: folders,
              selectedId: selectedFolderId,
              onSelected: onFolderSelected,
              onDelete: onDeleteFolder,
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? EmptyStateWidget(
                  icon: QuarkIcons.key_off_outlined,
                  headline: vaultIsEmpty
                      ? 'No passwords yet'
                      : 'No matching entries',
                  subtext: vaultIsEmpty
                      ? 'Add a login, or import them from another password '
                            'manager.'
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: floatingButtonClearance,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return VaultEntryTile(
                      entry: entry,
                      onTap: () => onTapEntry(entry.id),
                      onAction: onEntryAction == null
                          ? null
                          : (action) => onEntryAction(entry.id, action),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
