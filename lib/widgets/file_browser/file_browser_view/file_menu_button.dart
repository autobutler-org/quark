import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark_icons/quark_icons.dart';

/// The "more" menu on one file or folder, shared by the list and grid views.
///
/// [menu] decides which entries apply; a long press on the row opens the same
/// ones at the pointer (#2245).
class FileMenuButton extends StatelessWidget {
  const FileMenuButton({required this.menu, super.key});

  final FileMenu menu;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FileMenuAction>(
      icon: const Icon(QuarkIcons.more_vert),
      // The button's own context rather than the builder's: the popup route is
      // disposed as the menu pops, which is before an entry's action runs.
      itemBuilder: (_) => menu.entries(context),
    );
  }
}
