import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The rows of the sheet a phone's `+` button opens on the unlocked vault
/// (#4234): New entry, New folder and Import. Export is in the bar's More
/// menu instead.
///
/// Each row closes the sheet and then runs its action. The rows carry the
/// wide bar's chip keys, `vault_new_entry`, `vault_new_folder` and
/// `vault_import`, so a test or `.probe` script finds an action by one key at
/// every width.
class VaultCreateSheet extends StatelessWidget {
  /// Creates the rows; each callback runs its action.
  const VaultCreateSheet({
    required this.onNewEntry,
    required this.onNewFolder,
    required this.onImport,
    super.key,
  });

  /// Opens the sheet over [context] with these rows.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onNewEntry,
    required VoidCallback onNewFolder,
    required VoidCallback? onImport,
  }) => showQuarkSheet<void>(
    context,
    title: 'Add to your vault',
    builder: (_) => VaultCreateSheet(
      onNewEntry: onNewEntry,
      onNewFolder: onNewFolder,
      onImport: onImport,
    ),
  );

  /// Opens a blank entry.
  final VoidCallback onNewEntry;

  /// Asks for a folder's name and makes it.
  final VoidCallback onNewFolder;

  /// Picks a file to import. Null disables Import while one is running.
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    VoidCallback? closeThen(VoidCallback? action) => action == null
        ? null
        : () {
            Navigator.of(context).pop();
            action();
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('vault_new_entry'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(QuarkIcons.add),
          title: const Text('New entry'),
          onTap: closeThen(onNewEntry),
        ),
        ListTile(
          key: const ValueKey('vault_new_folder'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(QuarkIcons.create_new_folder_outlined),
          title: const Text('New folder'),
          onTap: closeThen(onNewFolder),
        ),
        ListTile(
          key: const ValueKey('vault_import'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(QuarkIcons.upload_rounded),
          title: const Text('Import'),
          enabled: onImport != null,
          onTap: closeThen(onImport),
        ),
      ],
    );
  }
}
