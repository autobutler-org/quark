import 'data_row.dart';

/// A spreadsheet's rows of cells, and the JSON form it is saved in.
class DataTable {
  List<DataRow> rows = [];

  DataTable(this.rows);
  DataTable.unnamed(this.rows);

  Map<String, dynamic> toJson() => {
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  static DataTable fromJson(Map<String, dynamic> json) {
    final rowsJson = (json['rows'] as List<dynamic>? ?? []);
    return DataTable(
      rowsJson.map((r) => DataRow.fromJson(r as List<dynamic>)).toList(),
    );
  }
}
