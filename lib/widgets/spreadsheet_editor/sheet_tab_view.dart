import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_format_palette.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One tab of a spreadsheet: the control bar and the formatting toolbar
/// above the grid they drive. The formatting colors come from the theme's
/// [QuarkTokens].
///
/// Both share the system clipboard, so cells copy to and paste from Google
/// Sheets and Excel. Where the browser blocks the clipboard (plain HTTP) they
/// fall back to an in-app one.
class SheetTabView extends StatelessWidget {
  final DataSheetController controller;
  final DataTable table;

  const SheetTabView({
    required this.controller,
    required this.table,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final clipboard = isClipboardAvailable
        ? const DataSheetClipboard(
            read: readClipboardText,
            write: writeClipboardText,
          )
        : DataSheetClipboard.memory;
    final tokens = QuarkTokens.of(context);
    return Column(
      children: [
        // Each bar scrolls sideways on its own; the scroller adds the wheel
        // mapping and edge chevrons every other toolbar has (#2770). Its
        // unbounded width also keeps the formatting toolbar a row on a phone
        // rather than folding it into a menu.
        for (final bar in [
          DataSheetControlBar(controller: controller, clipboard: clipboard),
          DataSheetFormatBar(
            controller: controller,
            textColors: sheetTextSwatches(tokens),
            fillColors: sheetFillSwatches(tokens),
          ),
        ])
          Align(
            alignment: Alignment.centerLeft,
            child: QuarkToolbarScroller(child: bar),
          ),
        Expanded(
          child: DataSheet(
            controller: controller,
            table: table,
            clipboard: clipboard,
          ),
        ),
      ],
    );
  }
}
