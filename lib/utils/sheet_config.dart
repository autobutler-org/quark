/// Tuning values for the spreadsheet editor.
abstract final class SheetConfig {
  /// How many blank rows an empty sheet opens with (#2779).
  static const int startingRows = 50;

  /// How many blank columns an empty sheet opens with: A to Z (#2779).
  static const int startingColumns = 26;
}
