import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/vault_entry_item.dart';
import '../../theme/quark_tokens.dart';

/// The folder filter of `VaultEntryList`: an "All" chip and one per folder,
/// in a row that scrolls sideways when it does not fit. With a folder chosen
/// and [onDelete] set, a delete button for that folder sits at the row's end,
/// outside the scroll, so it is always in reach.
///
/// Key prefixes: `vault_folder_all`, `vault_folder_<id>` and
/// `vault_folder_delete`.
class VaultFolderChips extends StatelessWidget {
  /// Creates the filter over [folders].
  const VaultFolderChips({
    required this.folders,
    required this.selectedId,
    required this.onSelected,
    this.onDelete,
    super.key,
  });

  /// The folders offered.
  final List<VaultFolderItem> folders;

  /// The folder chosen, or null for all.
  final int? selectedId;

  /// Called with the folder chosen, or null for all.
  final ValueChanged<int?> onSelected;

  /// Called with the chosen folder's id when its delete button is tapped.
  /// Null hides the button.
  final ValueChanged<int>? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final selectedId = this.selectedId;
    final onDelete = this.onDelete;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
            child: Row(
              spacing: tokens.spacingSm,
              children: [
                ChoiceChip(
                  key: const ValueKey('vault_folder_all'),
                  label: const Text('All'),
                  selected: selectedId == null,
                  onSelected: (_) => onSelected(null),
                ),
                for (final folder in folders)
                  ChoiceChip(
                    key: ValueKey('vault_folder_${folder.id}'),
                    label: Text(folder.name),
                    selected: selectedId == folder.id,
                    onSelected: (_) => onSelected(folder.id),
                  ),
              ],
            ),
          ),
        ),
        if (selectedId != null && onDelete != null)
          Padding(
            padding: EdgeInsetsDirectional.only(end: tokens.spacingSm),
            child: IconButton(
              key: const ValueKey('vault_folder_delete'),
              icon: const Icon(QuarkIcons.delete_outline),
              tooltip: 'Delete folder',
              onPressed: () => onDelete(selectedId),
            ),
          ),
      ],
    );
  }
}
