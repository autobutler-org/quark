import '../format/json_fields.dart';
import '../model/slide_color.dart';
import '../model/unset.dart';
import 'theme_color.dart';
import 'theme_palette.dart';
import 'theme_shape_style.dart';
import 'theme_text_role.dart';
import 'theme_text_style.dart';

/// A presentation's look: a palette of [colors] by `ThemeColor` role, a
/// [headingFont] and a [bodyFont], the text style of each `ThemeTextRole`,
/// and the [shapes] style new shapes and lines get.
///
/// The theme is stored in the `.qslide` file itself, so a deck looks the
/// same wherever it is opened and a customized theme needs no server.
/// Elements refer to it rather than copy it — a run with no color of its
/// own, a fill of `SlideColor.theme(ThemeColor.accent1)` — so switching
/// themes restyles the deck in one step. `SlideThemes` holds the built-in
/// ones.
///
/// ```dart
/// final custom = SlideThemes.cool.copyWith(
///   id: 'custom-1',
///   name: 'Ours',
///   colors: SlideThemes.cool.colors.copyWith({ThemeColor.accent1: brand}),
/// );
/// doc.setTheme(custom);
/// ```
class SlideTheme {
  /// Creates a theme. A `null` font is the platform's default.
  SlideTheme({
    required this.id,
    required this.name,
    required this.colors,
    this.headingFont,
    this.bodyFont,
    this.title = const ThemeTextStyle(fontSize: 60, heading: true),
    this.subtitle = const ThemeTextStyle(
      fontSize: 40,
      color: SlideColor.theme(ThemeColor.text2),
    ),
    this.body = const ThemeTextStyle(fontSize: 36),
    ThemeShapeStyle? shapes,
    this.extra = const {},
  }) : shapes = shapes ?? ThemeShapeStyle();

  /// A stable id; a built-in theme's is its name in lower camel case.
  final String id;

  /// The name a theme picker shows.
  final String name;

  /// The color of each role.
  final ThemePalette colors;

  /// The family titles are set in, or `null` for the platform's default.
  final String? headingFont;

  /// The family other text is set in, or `null` for the platform's
  /// default.
  final String? bodyFont;

  /// The style of [ThemeTextRole.title] text.
  final ThemeTextStyle title;

  /// The style of [ThemeTextRole.subtitle] text.
  final ThemeTextStyle subtitle;

  /// The style of [ThemeTextRole.body] text: every ordinary text box.
  final ThemeTextStyle body;

  /// How new shapes and lines are styled.
  final ThemeShapeStyle shapes;

  /// Fields a newer writer added that this version does not read.
  final JsonMap extra;

  /// The text style of [role].
  ThemeTextStyle textStyle(ThemeTextRole role) => switch (role) {
        ThemeTextRole.title => title,
        ThemeTextRole.subtitle => subtitle,
        ThemeTextRole.body => body,
      };

  /// The font family [style] is set in: [headingFont] or [bodyFont].
  String? fontOf(ThemeTextStyle style) =>
      style.heading ? headingFont : bodyFont;

  static const _known = {
    'id',
    'name',
    'colors',
    'headingFont',
    'bodyFont',
    'title',
    'subtitle',
    'body',
    'shapes',
  };

  /// Reads a theme from its `.qslide` object at [path]; a text style or
  /// shape style left out is the default.
  factory SlideTheme.fromJson(Object? value, String path) {
    final json = asObject(value, path);
    ThemeTextStyle? text(String key) => json[key] == null
        ? null
        : ThemeTextStyle.fromJson(json[key], '$path.$key');
    final defaults = SlideTheme(id: '', name: '', colors: ThemePalette({}));
    return SlideTheme(
      id: requireString(json, 'id', path),
      name: optionalString(json, 'name', path) ?? '',
      colors: json['colors'] == null
          ? ThemePalette({})
          : ThemePalette.fromJson(json['colors'], '$path.colors'),
      headingFont: optionalString(json, 'headingFont', path),
      bodyFont: optionalString(json, 'bodyFont', path),
      title: text('title') ?? defaults.title,
      subtitle: text('subtitle') ?? defaults.subtitle,
      body: text('body') ?? defaults.body,
      shapes: json['shapes'] == null
          ? null
          : ThemeShapeStyle.fromJson(json['shapes'], '$path.shapes'),
      extra: unknownFields(json, _known),
    );
  }

  /// The theme as its `.qslide` object.
  JsonMap toJson() => {
        ...extra,
        'id': id,
        'name': name,
        'colors': colors.toJson(),
        if (headingFont != null) 'headingFont': headingFont,
        if (bodyFont != null) 'bodyFont': bodyFont,
        'title': title.toJson(),
        'subtitle': subtitle.toJson(),
        'body': body.toJson(),
        'shapes': shapes.toJson(),
      };

  /// Returns a copy with the given fields replaced; pass `null` as a font
  /// to use the platform's default.
  SlideTheme copyWith({
    String? id,
    String? name,
    ThemePalette? colors,
    Object? headingFont = unset,
    Object? bodyFont = unset,
    ThemeTextStyle? title,
    ThemeTextStyle? subtitle,
    ThemeTextStyle? body,
    ThemeShapeStyle? shapes,
  }) =>
      SlideTheme(
        id: id ?? this.id,
        name: name ?? this.name,
        colors: colors ?? this.colors,
        headingFont: identical(headingFont, unset)
            ? this.headingFont
            : headingFont as String?,
        bodyFont:
            identical(bodyFont, unset) ? this.bodyFont : bodyFont as String?,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        body: body ?? this.body,
        shapes: shapes ?? this.shapes,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is SlideTheme &&
      other.id == id &&
      other.name == name &&
      other.colors == colors &&
      other.headingFont == headingFont &&
      other.bodyFont == bodyFont &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.body == body &&
      other.shapes == shapes &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        colors,
        headingFont,
        bodyFont,
        title,
        subtitle,
        body,
        shapes,
        jsonHash(extra),
      );

  @override
  String toString() => 'SlideTheme($id)';
}
