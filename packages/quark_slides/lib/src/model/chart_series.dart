import '../format/json_fields.dart';
import '../format/qslide_format_exception.dart';

/// One named row of numbers in a `ChartData`: a value per category.
///
/// In `.qslide` a series is an object; a `null` value reads as 0:
///
/// ```json
/// {"name": "Revenue", "values": [12, 30, 42.5]}
/// ```
class ChartSeries {
  /// Creates a series named [name] with [values], one per category.
  ChartSeries({
    this.name = '',
    List<double> values = const [],
    this.extra = const {},
  }) : values = List.unmodifiable(values);

  /// The series' name, as the legend shows it; may be empty.
  final String name;

  /// The value of each category, in category order; all finite.
  final List<double> values;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  static const _known = {'name', 'values'};

  /// Reads a series from its `.qslide` object at [path].
  factory ChartSeries.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final values = optionalList(json, 'values', path);
    return ChartSeries(
      name: optionalString(json, 'name', path) ?? '',
      values: [
        for (var i = 0; i < values.length; i++)
          switch (values[i]) {
            null => 0,
            final num n when n.isFinite => n.toDouble(),
            _ => throw QslideFormatException(
                'expected a number',
                path: '$path.values[$i]',
              ),
          },
      ],
      extra: unknownFields(json, _known),
    );
  }

  /// The series as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        if (name.isNotEmpty) 'name': name,
        'values': [for (final v in values) jsonNumber(v)],
      };

  /// Returns a copy with the given fields replaced.
  ChartSeries copyWith({String? name, List<double>? values}) => ChartSeries(
        name: name ?? this.name,
        values: values ?? this.values,
        extra: extra,
      );

  /// This series with [count] values: cut short, or padded with zeros.
  ChartSeries withLength(int count) => values.length == count
      ? this
      : copyWith(values: [
          for (var i = 0; i < count; i++) i < values.length ? values[i] : 0,
        ]);

  @override
  bool operator ==(Object other) =>
      other is ChartSeries &&
      other.name == name &&
      listEquals(other.values, values) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(values), jsonHash(extra));

  @override
  String toString() => 'ChartSeries($name, $values)';
}
