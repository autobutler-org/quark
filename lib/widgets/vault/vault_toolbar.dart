import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark_icons/quark_icons.dart';

/// The search box and folder filter above the vault's entry list.
class VaultToolbar extends StatelessWidget {
  final List<VaultFolder> folders;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onFolderSelected;

  const VaultToolbar({
    super.key,
    required this.folders,
    required this.onSearchChanged,
    required this.onFolderSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search vault...',
                prefixIcon: Icon(QuarkIcons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 8),
          if (folders.isNotEmpty)
            PopupMenuButton<int?>(
              icon: const Icon(QuarkIcons.folder_outlined),
              tooltip: 'Filter by folder',
              onSelected: onFolderSelected,
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('All')),
                ...folders.map(
                  (f) => PopupMenuItem(value: f.id, child: Text(f.name)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
