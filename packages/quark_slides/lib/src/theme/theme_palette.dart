import '../format/json_fields.dart';
import '../model/slide_color.dart';
import 'theme_color.dart';

/// The literal color of every [ThemeColor] role in a theme.
///
/// A role the palette leaves out is its [ThemeColor.fallback]. In `.qslide`
/// a palette is an object from role name to `#RRGGBB` or `#RRGGBBAA`:
///
/// ```json
/// {"background": "#FFFFFF", "text": "#1C1B1F", "accent1": "#3366FF"}
/// ```
class ThemePalette {
  /// Creates a palette from [colors], each `0xAARRGGBB`.
  ThemePalette(Map<ThemeColor, int> colors, {this.extra = const {}})
      : _colors = Map.unmodifiable(colors);

  final Map<ThemeColor, int> _colors;

  /// Fields a newer writer added that this version does not read — roles
  /// it added among them.
  final JsonMap extra;

  /// The color of [role], `0xAARRGGBB`.
  int operator [](ThemeColor role) => _colors[role] ?? role.fallback;

  /// Reads a palette from its `.qslide` object at [path].
  factory ThemePalette.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    final known = ThemeColor.values.asNameMap();
    return ThemePalette(
      {
        for (final MapEntry(:key, :value) in json.entries)
          if (known[key] case final role?)
            role: SlideColor.parse(
              value is String ? value : '',
              path: '$path.$key',
            ).argb,
      },
      extra: unknownFields(json, known.keys.toSet()),
    );
  }

  /// The palette as its `.qslide` object, every role written out.
  JsonMap toJson() => {
        ...extra,
        for (final role in ThemeColor.values)
          role.name: SlideColor(this[role]).toHex(),
      };

  /// Returns a copy with the colors in [colors] replaced.
  ThemePalette copyWith(Map<ThemeColor, int> colors) => ThemePalette(
        {
          for (final role in ThemeColor.values) role: this[role],
          ...colors,
        },
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is ThemePalette &&
      ThemeColor.values.every((role) => other[role] == this[role]) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(ThemeColor.values.map((role) => this[role])),
        jsonHash(extra),
      );
}
