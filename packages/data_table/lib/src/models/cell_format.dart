/// Where a cell's text sits across its width. A cell with no alignment set
/// keeps the sheet's default, the left edge.
enum CellAlign { left, center, right }

/// How a cell displays a number. Formats change only the display: the stored
/// value and every formula that reads it see the raw text.
enum CellNumberFormat {
  /// The value as typed, or as a formula computed it.
  general,

  /// Grouped thousands with fixed decimals: `1,234.50`.
  number,

  /// A dollar amount with fixed decimals: `$1,234.50`, `-$3.00`.
  currency,

  /// The value times 100 with a percent sign: `0.25` shows `25.00%`.
  percent,

  /// A spreadsheet serial day (days since 1899-12-30, as Google Sheets and
  /// Excel count them) shown as `yyyy-mm-dd`.
  date,
}

/// One cell's formatting: bold, italic, text and fill color, horizontal
/// alignment, and number format.
///
/// Immutable, and sparse: a sheet keeps one only for cells that have one, and
/// [plain] is every cell's default. Colors are 32-bit ARGB integers, so the
/// model needs no Flutter import and saves as plain JSON. [toJson] writes only
/// the fields that are set, and [fromJson] reads anything it does not
/// recognize as the default, so files written by a newer or older editor load.
///
/// ```dart
/// final heading = CellFormat.plain.withBold(true).withAlign(CellAlign.center);
/// ```
class CellFormat {
  /// Bold text.
  final bool bold;

  /// Italic text.
  final bool italic;

  /// The text color as ARGB, or null for the theme's text color.
  final int? textColor;

  /// The background color as ARGB, or null for no fill.
  final int? fillColor;

  /// The horizontal alignment, or null for the default.
  final CellAlign? align;

  /// How a numeric value is displayed.
  final CellNumberFormat numberFormat;

  /// Decimal places for [CellNumberFormat.number], [CellNumberFormat.currency]
  /// and [CellNumberFormat.percent], or null for [defaultDecimals].
  final int? decimals;

  /// The most decimal places a format shows.
  static const int maxDecimals = 10;

  /// The decimal places a number format shows until the user changes them.
  static const int defaultDecimals = 2;

  /// A format; every field defaults to plain.
  const CellFormat({
    this.bold = false,
    this.italic = false,
    this.textColor,
    this.fillColor,
    this.align,
    this.numberFormat = CellNumberFormat.general,
    this.decimals,
  });

  /// No formatting at all: every cell's default.
  static const CellFormat plain = CellFormat();

  /// True when this format changes nothing.
  bool get isPlain => this == plain;

  /// The decimal places the number format shows.
  int get effectiveDecimals => decimals ?? defaultDecimals;

  /// This format with [bold] set to [value].
  CellFormat withBold(bool value) => _copy(bold: value);

  /// This format with [italic] set to [value].
  CellFormat withItalic(bool value) => _copy(italic: value);

  /// This format with [textColor] set to [argb]; null restores the default.
  CellFormat withTextColor(int? argb) => _copy(textColor: () => argb);

  /// This format with [fillColor] set to [argb]; null removes the fill.
  CellFormat withFillColor(int? argb) => _copy(fillColor: () => argb);

  /// This format with [align] set to [value]; null restores the default.
  CellFormat withAlign(CellAlign? value) => _copy(align: () => value);

  /// This format with [numberFormat] set to [value].
  CellFormat withNumberFormat(CellNumberFormat value) =>
      _copy(numberFormat: value);

  /// This format with [decimals] set to [value], clamped to
  /// 0..[maxDecimals]; null restores [defaultDecimals].
  CellFormat withDecimals(int? value) =>
      _copy(decimals: () => value?.clamp(0, maxDecimals));

  CellFormat _copy({
    bool? bold,
    bool? italic,
    int? Function()? textColor,
    int? Function()? fillColor,
    CellAlign? Function()? align,
    CellNumberFormat? numberFormat,
    int? Function()? decimals,
  }) =>
      CellFormat(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        textColor: textColor != null ? textColor() : this.textColor,
        fillColor: fillColor != null ? fillColor() : this.fillColor,
        align: align != null ? align() : this.align,
        numberFormat: numberFormat ?? this.numberFormat,
        decimals: decimals != null ? decimals() : this.decimals,
      );

  /// The fields that are set, by name; a plain format is an empty map.
  Map<String, Object> toJson() => {
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (textColor != null) 'textColor': textColor!,
        if (fillColor != null) 'fillColor': fillColor!,
        if (align != null) 'align': align!.name,
        if (numberFormat != CellNumberFormat.general)
          'numberFormat': numberFormat.name,
        if (decimals != null) 'decimals': decimals!,
      };

  /// Reads what [toJson] wrote. A missing, mistyped or unknown value reads
  /// as the default for that field.
  factory CellFormat.fromJson(Map<dynamic, dynamic> json) {
    T? named<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    int? argb(Object? v) => v is int ? v & 0xFFFFFFFF : null;
    final decimals = json['decimals'];
    return CellFormat(
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      textColor: argb(json['textColor']),
      fillColor: argb(json['fillColor']),
      align: named(CellAlign.values, json['align']),
      numberFormat: named(CellNumberFormat.values, json['numberFormat']) ??
          CellNumberFormat.general,
      decimals: decimals is int && decimals >= 0
          ? decimals.clamp(0, maxDecimals)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CellFormat &&
      other.bold == bold &&
      other.italic == italic &&
      other.textColor == textColor &&
      other.fillColor == fillColor &&
      other.align == align &&
      other.numberFormat == numberFormat &&
      other.decimals == decimals;

  @override
  int get hashCode => Object.hash(
        bold,
        italic,
        textColor,
        fillColor,
        align,
        numberFormat,
        decimals,
      );

  @override
  String toString() => 'CellFormat(${toJson()})';
}
