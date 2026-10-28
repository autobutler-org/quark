import 'package:flutter/material.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark/widgets/vault/vault_export_menu.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The unlocked vault's second bar row (#3589): "Passwords" on the left, and
/// New entry, New folder, Import and Export on the right.
///
/// Six actions did not fit a phone's top bar, which scrolled Lock off the
/// edge. Here, below `QuarkAppBarBottom.collapseBreakpoint`, the four give way
/// to a menu labeled "Manage", so the top bar keeps room for Lock.
///
/// Only the chips or the menu are ever on screen, so the menu's entries carry
/// the chips' keys: `vault_new_entry`, `vault_new_folder`, `vault_import`, and
/// `vault_export` with `vault_export_<format>` (`json`, `csv`) under it.
/// `app_bar_bottom_menu` is on the chip that opens the menu.
class VaultBarBottom extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the row; each callback runs its action.
  const VaultBarBottom({
    required this.onNewEntry,
    required this.onNewFolder,
    required this.onImport,
    required this.onExport,
    super.key,
  });

  /// Opens a blank entry.
  final VoidCallback onNewEntry;

  /// Asks for a folder's name and makes it.
  final VoidCallback onNewFolder;

  /// Picks a file to import. Null disables Import while one is running.
  final VoidCallback? onImport;

  /// Called with the export format chosen.
  final ValueChanged<VaultExportFormat> onExport;

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return QuarkAppBarBottom(
      lead: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Passwords',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
        ),
      ),
      actions: [
        QuarkBarChip(
          key: const ValueKey('vault_new_entry'),
          icon: QuarkIcons.add_rounded,
          label: 'New entry',
          onPressed: onNewEntry,
        ),
        QuarkBarChip(
          key: const ValueKey('vault_new_folder'),
          icon: QuarkIcons.create_new_folder_outlined,
          label: 'New folder',
          tooltip: 'New folder',
          onPressed: onNewFolder,
        ),
        QuarkBarChip(
          key: const ValueKey('vault_import'),
          icon: QuarkIcons.upload_rounded,
          label: 'Import',
          onPressed: onImport,
        ),
        VaultExportMenu(onExport: onExport),
      ],
      menuLabel: 'Manage',
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('vault_new_entry'),
          leadingIcon: const Icon(QuarkIcons.add_rounded),
          onPressed: onNewEntry,
          child: const Text('New entry'),
        ),
        MenuItemButton(
          key: const ValueKey('vault_new_folder'),
          leadingIcon: const Icon(QuarkIcons.create_new_folder_outlined),
          onPressed: onNewFolder,
          child: const Text('New folder'),
        ),
        MenuItemButton(
          key: const ValueKey('vault_import'),
          leadingIcon: const Icon(QuarkIcons.upload_rounded),
          onPressed: onImport,
          child: const Text('Import'),
        ),
        SubmenuButton(
          key: const ValueKey('vault_export'),
          leadingIcon: const Icon(QuarkIcons.download_outlined),
          menuChildren: [
            for (final format in VaultExportFormat.values)
              MenuItemButton(
                key: ValueKey('vault_export_${format.name}'),
                leadingIcon: const Icon(QuarkIcons.download_outlined),
                onPressed: () => onExport(format),
                child: Text('Export as ${format.name.toUpperCase()}'),
              ),
          ],
          child: const Text('Export'),
        ),
      ],
    );
  }
}
