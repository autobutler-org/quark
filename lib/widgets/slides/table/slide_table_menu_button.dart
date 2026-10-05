import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/table/slide_table_picker.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide tool row's table button (#1160): opens a [SlideTablePicker]
/// that arms the table tool or inserts a table in the middle of the slide.
/// It is lit while the table tool is active, and the picker starts at the
/// size that tool draws.
///
/// Key prefixes: `slide_tool_table` on the button; the picker's own.
class SlideTableMenuButton extends StatelessWidget {
  /// The table button for [actions].
  const SlideTableMenuButton({required this.actions, super.key});

  /// What the picker's choices do.
  final SlideToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final size = actions.tableToolSize;
    return MenuAnchor(
      menuChildren: [
        SlideTablePicker(
          rows: size.rows,
          columns: size.columns,
          onDraw: actions.drawTable,
          onInsert: actions.insertTable,
        ),
      ],
      builder: (context, menu, _) => QuarkBarIconButton(
        key: const ValueKey('slide_tool_table'),
        icon: QuarkIcons.insert_table,
        tooltip: 'Insert table',
        selected: actions.tableToolActive,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
