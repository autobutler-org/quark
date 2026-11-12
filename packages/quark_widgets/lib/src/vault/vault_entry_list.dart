import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../models/vault_entry_item.dart';
import '../theme/quark_tokens.dart';
import 'vault_entry_list/vault_entry_tile.dart';
import 'vault_entry_list/vault_folder_chips.dart';

/// An unlocked vault's entries: a search box, a folder filter when there are
/// folders, and one row per entry.
///
/// Filtering is the caller's: [entries] is already what the search and the
/// folder leave, and the box and chips only report what was typed or chosen.
/// [vaultIsEmpty] tells an empty vault apart from a search that matched
/// nothing.
///
/// Key prefixes: `vault_search` on the search box, `vault_entry_<id>` on each
/// row, `vault_folder_all` and `vault_folder_<id>` on the folder chips, and
/// `vault_folder_delete` on the chosen folder's delete button.
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

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onFolderSelected = this.onFolderSelected;
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
          child: TextFormField(
            key: const ValueKey('vault_search'),
            initialValue: initialQuery,
            decoration: const InputDecoration(
              hintText: 'Search the vault',
              prefixIcon: Icon(QuarkIcons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearchChanged,
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
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return VaultEntryTile(
                      entry: entry,
                      onTap: () => onTapEntry(entry.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
