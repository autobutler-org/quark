import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The vault page's Export chip, which opens a menu of the formats an export
/// can be saved in. On a phone, where the bar holds two actions, it is the
/// More chip instead, with the same entries (#4234).
///
/// Keys: `vault_export` on the chip, `vault_export_<format>` (`json`, `csv`)
/// on its entries.
class VaultExportMenu extends StatelessWidget {
  /// Creates the menu.
  const VaultExportMenu({
    required this.onExport,
    this.asMore = false,
    super.key,
  });

  /// Called with the format chosen.
  final ValueChanged<VaultExportFormat> onExport;

  /// Whether the chip reads "More", for a phone's bar.
  final bool asMore;

  @override
  Widget build(BuildContext context) {
    return QuarkBarMenuButton(
      buttonKey: const ValueKey('vault_export'),
      icon: asMore
          ? QuarkIcons.more_horiz_rounded
          : QuarkIcons.download_outlined,
      label: asMore ? 'More' : 'Export',
      tooltip: asMore ? 'More' : 'Export',
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
    );
  }
}
