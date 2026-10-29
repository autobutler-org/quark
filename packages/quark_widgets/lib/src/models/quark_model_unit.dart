/// The unit one of a 3D model file's coordinates stands for, as the user
/// picks it in `QuarkModelViewer` (#3228). A model file does not record its
/// unit, so the viewer shows bare numbers until the user names one; picking
/// a unit labels the numbers and does not change them.
enum QuarkModelUnit {
  /// Whatever the file was written in: sizes carry no unit name, and a
  /// print-bed check reads them as millimeters, which is what STL files
  /// almost always hold.
  file(label: 'File units', symbol: '', inMillimeters: 1),

  /// One unit is a millimeter.
  millimeters(label: 'Millimeters', symbol: 'mm', inMillimeters: 1),

  /// One unit is an inch.
  inches(label: 'Inches', symbol: 'in', inMillimeters: 25.4);

  const QuarkModelUnit({
    required this.label,
    required this.symbol,
    required this.inMillimeters,
  });

  /// The unit's name in a menu: "Millimeters".
  final String label;

  /// The unit's short name after a number: `mm`, or empty for [file].
  final String symbol;

  /// How many millimeters one unit is, for comparing with a print bed.
  final double inMillimeters;
}
