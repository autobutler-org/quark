import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_search_field.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Inline search. When collapsed shows just the search icon pinned to the
/// right; when expanded the field fills all available width.
///
/// This widget lives inside an [Expanded] in the top row, so it always has
/// bounded horizontal constraints — no double.infinity needed.
///
/// Probe keys: `file_top_bar_search`.
class FileTopBarSearchArea extends StatelessWidget {
  const FileTopBarSearchArea({
    required this.expanded,
    required this.controller,
    required this.focusNode,
    required this.onOpen,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final bool expanded;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      // Fill all available space with the text field.
      return FileTopBarSearchField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onClose: onClose,
      );
    }

    // Collapsed: push the search icon to the trailing edge. On a phone this
    // is the bar's last bit of slack, so the button scales down rather than
    // overflow when a jobs badge or a long name takes the room.
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: QuarkBarIconButton(
          key: const ValueKey('file_top_bar_search'),
          icon: QuarkIcons.search_rounded,
          onPressed: onOpen,
          tooltip: 'Search',
        ),
      ),
    );
  }
}
