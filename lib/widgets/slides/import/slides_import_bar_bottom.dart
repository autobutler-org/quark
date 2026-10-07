import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Slides page's second bar row (#1171): what the list shows on the
/// left, and Import PowerPoint on the right.
///
/// A PowerPoint file can come from the Quark or from this device, so the
/// chip opens a menu of the two. Below `QuarkAppBarBottom.collapseBreakpoint`
/// the chip gives way to a menu labeled "Import" holding the same two
/// choices, so a phone still says what it does.
///
/// Key prefixes: `slides_import` on the chip, `app_bar_bottom_menu` on the
/// phone menu, and `slides_import_from_quark` and
/// `slides_import_from_device` on the entries of either.
///
/// ```dart
/// QuarkAppBar(
///   label: 'Slides',
///   icon: QuarkIcons.slideshow_outlined,
///   bottom: SlidesImportBarBottom(
///     onImportFromQuark: pickOnQuark,
///     onImportFromDevice: pickOnDevice,
///   ),
/// );
/// ```
class SlidesImportBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  /// Creates the row; each callback starts an import from its source.
  const SlidesImportBarBottom({
    required this.onImportFromQuark,
    required this.onImportFromDevice,
    super.key,
  });

  /// Picks a PowerPoint file already on the Quark and imports it.
  final VoidCallback onImportFromQuark;

  /// Picks a PowerPoint file on this device, uploads it and imports it.
  final VoidCallback onImportFromDevice;

  static const _tooltip = 'Import a PowerPoint file as a presentation';

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    // Only one of the chip's menu and the phone menu is ever on screen, so
    // they share these entries and their keys.
    final entries = [
      MenuItemButton(
        key: const ValueKey('slides_import_from_quark'),
        leadingIcon: const Icon(QuarkIcons.folder_open_outlined),
        onPressed: onImportFromQuark,
        child: const Text('From your Quark'),
      ),
      MenuItemButton(
        key: const ValueKey('slides_import_from_device'),
        leadingIcon: const Icon(QuarkIcons.upload_rounded),
        onPressed: onImportFromDevice,
        child: const Text('From this device'),
      ),
    ];
    return QuarkAppBarBottom(
      lead: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Presentations',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
        ),
      ),
      actions: [
        MenuAnchor(
          menuChildren: entries,
          builder: (context, controller, _) => QuarkBarChip(
            key: const ValueKey('slides_import'),
            icon: QuarkIcons.import_file,
            label: 'Import PowerPoint',
            tooltip: _tooltip,
            keepLabel: true,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ],
      menuLabel: 'Import',
      menuIcon: QuarkIcons.import_file,
      menuChildren: entries,
    );
  }
}
