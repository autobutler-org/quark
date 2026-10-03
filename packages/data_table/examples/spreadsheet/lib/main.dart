// ignore_for_file: avoid_print

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;

void main() {
  final table = DataTable([
    DataRow([DataCell('Alice'), DataCell('30'), DataCell('New York')]),
    DataRow([DataCell('Bob'), DataCell('25'), DataCell('Los Angeles')]),
    DataRow([DataCell('Charlie'), DataCell('35'), DataCell('Chicago')]),
  ]);
  final sheetController = DataSheetController.fromTable(table);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('data_sheet example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DataSheetControlBar(controller: sheetController),
              DataSheetFormatBar(controller: sheetController),
              Expanded(
                child: DataSheet(
                  controller: sheetController,
                  table: table,
                  beforeCellValueChanged: (value, row, col) {
                    print('Cell at row $row, column $col changing to "$value"');
                    print('Table before:');
                    for (var r = 0; r < table.rows.length; r++) {
                      var rowData = table.rows[r].cells
                          .map((cell) => cell.value)
                          .join(', ');
                      print('Row $r: $rowData');
                    }
                    return true;
                  },
                  afterCellValueChanged: (value, row, col, _) {
                    print('Cell at row $row, column $col changed to "$value"');
                    print('Table after:');
                    for (var r = 0; r < table.rows.length; r++) {
                      var rowData = table.rows[r].cells
                          .map((cell) => cell.value)
                          .join(', ');
                      print('Row $r: $rowData');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
