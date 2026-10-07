part of 'slide_element.dart';

/// A chart of [kind] drawn from its own small table of numbers, [data]:
/// bars, horizontal bars, lines, a pie or areas, dressed as [options] say.
///
/// Each series — each slice, in a pie — is colored by [colorOf]: the entry
/// of [colors] at its index, or else the theme's accents in turn
/// ([defaultPalette]), so a chart follows the deck's theme until it is
/// given colors of its own. A pie draws its first series only.
///
/// The chart is moved, resized and rotated as any element is; what is
/// inside the frame — title, legend, axes, plot — is laid out as it is
/// drawn, so it never needs refitting.
///
/// In `.qslide`:
///
/// ```json
/// {"id": "c1", "type": "chart", "kind": "bar",
///  "frame": {"x": 360, "y": 200, "width": 1200, "height": 700},
///  "categories": ["Q1", "Q2", "Q3"],
///  "series": [{"name": "Revenue", "values": [12, 30, 42]}],
///  "colors": ["theme:accent2"], "title": "Sales", "dataLabels": true}
/// ```
///
/// A `kind` this version does not know reads the whole element as an
/// [UnknownElement], kept verbatim.
class ChartElement extends SlideElement {
  /// Creates a chart.
  ChartElement({
    required super.id,
    required super.frame,
    this.kind = ChartKind.bar,
    ChartData? data,
    this.options = const ChartOptions(),
    List<SlideColor> colors = const [],
    super.extra,
  })  : data = data ?? ChartData(),
        colors = List.unmodifiable(colors);

  /// The `type` discriminator, `chart`.
  static const typeName = 'chart';

  /// The colors series take, in order, when [colors] leaves them unset: the
  /// theme's six accents.
  static const defaultPalette = [
    SlideColor.theme(ThemeColor.accent1),
    SlideColor.theme(ThemeColor.accent2),
    SlideColor.theme(ThemeColor.accent3),
    SlideColor.theme(ThemeColor.accent4),
    SlideColor.theme(ThemeColor.accent5),
    SlideColor.theme(ThemeColor.accent6),
  ];

  static const _known = {
    'id',
    'type',
    'frame',
    'kind',
    'categories',
    'series',
    'colors',
    'title',
    'legend',
    'dataLabels',
    'gridlines',
    'categoryAxisTitle',
    'valueAxisTitle',
  };

  /// What kind of chart it is.
  final ChartKind kind;

  /// The numbers drawn.
  final ChartData data;

  /// The title, legend, labels, gridlines and axis titles.
  final ChartOptions options;

  /// The color of each series — each slice, in a pie — by index; those
  /// past its end take [defaultPalette].
  final List<SlideColor> colors;

  /// The color of series [index] (slice [index] in a pie).
  SlideColor colorOf(int index) => index < colors.length
      ? colors[index]
      : defaultPalette[index % defaultPalette.length];

  /// What is drawn, one entry per series or (in a pie) per slice: its name
  /// and color, as the legend lists them.
  List<({String name, SlideColor color})> get legendEntries => [
        if (kind == ChartKind.pie)
          for (final (i, c) in data.categories.indexed)
            (name: c, color: colorOf(i))
        else
          for (final (i, s) in data.series.indexed)
            (name: s.name, color: colorOf(i)),
      ];

  @override
  String get type => typeName;

  @override
  JsonMap _fieldsToJson() => {
        'kind': kind.name,
        ...data.toJson(),
        if (colors.isNotEmpty) 'colors': [for (final c in colors) c.toHex()],
        if (options.title.isNotEmpty) 'title': options.title,
        if (!options.showLegend) 'legend': false,
        if (options.showDataLabels) 'dataLabels': true,
        if (!options.showGridlines) 'gridlines': false,
        if (options.categoryAxisTitle.isNotEmpty)
          'categoryAxisTitle': options.categoryAxisTitle,
        if (options.valueAxisTitle.isNotEmpty)
          'valueAxisTitle': options.valueAxisTitle,
      };

  /// Reads a chart whose `kind` is [kind] from its `.qslide` object.
  static ChartElement _fromJson(
    JsonMap json,
    String id,
    ElementFrame frame,
    ChartKind kind,
    String path,
  ) {
    final colors = optionalList(json, 'colors', path);
    // A pie colors each category, so it may need as many colors as those.
    if (colors.length > ChartData.maxCategories) {
      throw QslideFormatException(
        'a chart has at most ${ChartData.maxCategories} colors',
        path: '$path.colors',
      );
    }
    return ChartElement(
      id: id,
      frame: frame,
      kind: kind,
      data: ChartData.fromJson(json, path),
      colors: [
        for (var i = 0; i < colors.length; i++)
          switch (colors[i]) {
            final String hex => SlideColor.parse(hex, path: '$path.colors[$i]'),
            _ => throw QslideFormatException(
                'expected a color',
                path: '$path.colors[$i]',
              ),
          },
      ],
      options: ChartOptions(
        title: optionalString(json, 'title', path) ?? '',
        showLegend: optionalBool(json, 'legend', path, true),
        showDataLabels: optionalBool(json, 'dataLabels', path, false),
        showGridlines: optionalBool(json, 'gridlines', path, true),
        categoryAxisTitle:
            optionalString(json, 'categoryAxisTitle', path) ?? '',
        valueAxisTitle: optionalString(json, 'valueAxisTitle', path) ?? '',
      ),
      extra: unknownFields(json, _known),
    );
  }

  /// Returns a copy with the given fields replaced.
  ChartElement copyWith({
    String? id,
    ElementFrame? frame,
    ChartKind? kind,
    ChartData? data,
    ChartOptions? options,
    List<SlideColor>? colors,
  }) =>
      ChartElement(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        kind: kind ?? this.kind,
        data: data ?? this.data,
        options: options ?? this.options,
        colors: colors ?? this.colors,
        extra: extra,
      );

  @override
  ChartElement withFrame(ElementFrame frame) => copyWith(frame: frame);

  @override
  ChartElement withId(String id) => copyWith(id: id);

  @override
  bool operator ==(Object other) =>
      other is ChartElement &&
      other.id == id &&
      other.frame == frame &&
      other.kind == kind &&
      other.data == data &&
      other.options == options &&
      listEquals(other.colors, colors) &&
      jsonEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
        id,
        frame,
        kind,
        data,
        options,
        Object.hashAll(colors),
        jsonHash(extra),
      );
}
