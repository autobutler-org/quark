import 'package:flutter/foundation.dart';

/// A 3D printer's build volume, for the model viewer's print-bed check
/// (#3228): [width] by [depth] across the bed and [height] up, all in
/// millimeters.
///
/// ```dart
/// final fits = QuarkPrintBed.common.first.fits(
///   width: 120,
///   depth: 80,
///   height: 40,
/// );
/// ```
@immutable
class QuarkPrintBed {
  /// Creates a bed called [name], with [id] naming it in keys.
  const QuarkPrintBed({
    required this.id,
    required this.name,
    required this.width,
    required this.depth,
    required this.height,
  });

  /// A few common printers, smallest first.
  static const List<QuarkPrintBed> common = [
    QuarkPrintBed(
      id: 'prusa_mini',
      name: 'Prusa MINI',
      width: 180,
      depth: 180,
      height: 180,
    ),
    QuarkPrintBed(
      id: 'ender_3',
      name: 'Creality Ender-3',
      width: 220,
      depth: 220,
      height: 250,
    ),
    QuarkPrintBed(
      id: 'prusa_mk4',
      name: 'Prusa MK4',
      width: 250,
      depth: 210,
      height: 220,
    ),
    QuarkPrintBed(
      id: 'bambu_x1',
      name: 'Bambu Lab X1 / P1',
      width: 256,
      depth: 256,
      height: 256,
    ),
  ];

  /// Names the bed in keys: `model_viewer_bed_option_<id>`.
  final String id;

  /// The printer's name, as the menu shows it.
  final String name;

  /// The bed's size along its x axis, in millimeters.
  final double width;

  /// The bed's size along its y axis, in millimeters.
  final double depth;

  /// How tall a print can be, in millimeters.
  final double height;

  /// Whether a box [width] by [depth] across and [height] tall, all in
  /// millimeters, fits standing as it is, turned a quarter on the bed if
  /// that is what it takes.
  bool fits({
    required double width,
    required double depth,
    required double height,
  }) {
    final across = width < depth ? (width, depth) : (depth, width);
    final bed = this.width < this.depth
        ? (this.width, this.depth)
        : (this.depth, this.width);
    return across.$1 <= bed.$1 && across.$2 <= bed.$2 && height <= this.height;
  }

  @override
  bool operator ==(Object other) =>
      other is QuarkPrintBed &&
      other.id == id &&
      other.name == name &&
      other.width == width &&
      other.depth == depth &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, name, width, depth, height);
}
