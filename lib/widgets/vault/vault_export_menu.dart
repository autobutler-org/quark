import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The vault page's Export chip, which opens a menu of the formats an export
/// can be saved in.
///
/// Keys: `vault_export` on the chip, `vault_export_<format>` (`json`, `csv`)
/// on its entries.
class VaultExportMenu extends StatelessWidget {
  /// Creates the menu.
  const VaultExportMenu({required this.onExport, super.key});

  /// Called with the format chosen.
  final ValueChanged<VaultExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final format in VaultExportFormat.values)
          MenuItemButton(
            key: ValueKey('vault_export_${format.name}'),
            onPressed: () => onExport(format),
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.download_outlined),
              label: Text('Export as ${format.name.toUpperCase()}'),
            ),
          ),
      ],
      builder: (context, controller, _) => QuarkBarChip(
        key: const ValueKey('vault_export'),
        icon: QuarkIcons.download_outlined,
        label: 'Export',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
