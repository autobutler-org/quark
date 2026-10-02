import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:quark/utils/clipboard_utils.dart';

/// One tab of a spreadsheet: the control bar above the grid it drives.
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
    return Column(
      children: [
        DataSheetControlBar(controller: controller, clipboard: clipboard),
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
