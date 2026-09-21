import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/widgets/vault/entry_tile.dart';
import 'package:quark/widgets/vault/vault_toolbar.dart';
import 'package:quark_icons/quark_icons.dart';

/// The unlocked vault: the entries, filtered by the search box and the chosen folder.
class VaultEntryList extends StatelessWidget {
  /// The entries left after the search box and folder filter.
  final List<VaultEntryItem> entries;

  /// Whether the vault holds no entries at all — an empty [entries] means
  /// "no matching entries" otherwise.
  final bool vaultIsEmpty;

  final List<VaultFolder> folders;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onFolderSelected;
  final ValueChanged<int> onTapEntry;

  const VaultEntryList({
    super.key,
    required this.entries,
    required this.vaultIsEmpty,
    required this.folders,
    required this.onSearchChanged,
    required this.onFolderSelected,
    required this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VaultToolbar(
          folders: folders,
          onSearchChanged: onSearchChanged,
          onFolderSelected: onFolderSelected,
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        QuarkIcons.key_off_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        vaultIsEmpty
                            ? 'No credentials yet'
                            : 'No matching entries',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (vaultIsEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Tap + to add your first password'),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return EntryTile(
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
