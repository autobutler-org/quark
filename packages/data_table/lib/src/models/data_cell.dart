/// One cell's raw value, as typed — a formula stays a formula here.
class DataCell {
  String value;

  DataCell(this.value);
  DataCell.unnamed(this.value);

  String toJson() => value;

  static DataCell fromJson(dynamic json) => DataCell(json?.toString() ?? '');
}
