import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The "more" menu on one file or folder, shared by the list and grid views.
///
/// [menu] decides which entries apply; a long press or a right-click on the
/// row opens the same ones at the pointer (#2245, #2267).
class FileMenuButton extends StatelessWidget {
  const FileMenuButton({required this.menu, super.key});

  final FileMenu menu;

  @override
  Widget build(BuildContext context) {
    // The button's own context, which outlives the menu, is what the entries
    // dispatch against.
    return QuarkMenuButton(entries: menu.entries(context));
  }
}
