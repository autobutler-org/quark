import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/quark_model_unit.dart';
import '../../models/quark_print_bed.dart';
import '../../theme/quark_tokens.dart';
import '../quark_model_measurements.dart';
import '../quark_model_mesh.dart';
import 'model_viewer_stats/model_viewer_choice_chip.dart';

/// The strip under a `QuarkModelViewer`'s canvas: the model's bounding-box
/// size along each axis, its surface area and volume, its triangle and
/// vertex counts, whether it fits the chosen print bed, how to move it, and
/// the caller's status line. The parts wrap onto more lines when the width
/// runs out.
///
/// Sizes are in the file's own unit, which a model file does not record
/// (STL is usually millimeters), so they carry no unit name until the user
/// picks one with the units chip (#3228). The volume says when the mesh is
/// open, since it is only an estimate then. The bed chip picks one of
/// [printBeds] to check the model against, standing as the file has it and
/// turned a quarter if that helps; in file units the check reads them as
/// millimeters and says so.
///
/// Key prefixes: `model_viewer_size`, `model_viewer_area`,
/// `model_viewer_volume`, `model_viewer_triangles`, `model_viewer_vertices`,
/// `model_viewer_unit` (and `model_viewer_unit_option_<unit name>` on its
/// menu rows), `model_viewer_bed` (and `model_viewer_bed_option_<bed id>`,
/// `none` for no bed), `model_viewer_bed_fit`, `model_viewer_hint` and
/// `model_viewer_status`.
///
/// ```dart
/// ModelViewerStats(
///   mesh: mesh,
///   measurements: mesh.measure(),
///   unit: QuarkModelUnit.millimeters,
///   onUnitChanged: setUnit,
///   printBed: QuarkPrintBed.common.first,
///   onPrintBedChanged: setPrintBed,
///   statusLabel: 'part.stl',
/// );
/// ```
class ModelViewerStats extends StatelessWidget {
  /// Creates the strip for [mesh].
  const ModelViewerStats({
    required this.mesh,
    required this.measurements,
    this.unit = QuarkModelUnit.file,
    this.onUnitChanged,
    this.printBed,
    this.printBeds = QuarkPrintBed.common,
    this.onPrintBedChanged,
    this.statusLabel,
    super.key,
  });

  /// The model described.
  final QuarkModelMesh mesh;

  /// [mesh]'s volume and area.
  final QuarkModelMeasurements measurements;

  /// The unit the numbers are labeled in.
  final QuarkModelUnit unit;

  /// Called with the unit the user picks. Null leaves the units chip out.
  final ValueChanged<QuarkModelUnit>? onUnitChanged;

  /// The bed the model is checked against, null for none.
  final QuarkPrintBed? printBed;

  /// The beds the bed chip offers.
  final List<QuarkPrintBed> printBeds;

  /// Called with the bed the user picks, or null for none. Null leaves the
  /// bed chip out.
  final ValueChanged<QuarkPrintBed?>? onPrintBedChanged;

  /// A line from the caller, shown after the counts; null shows nothing.
  final String? statusLabel;

  /// The touch and mouse gestures, spelled out for someone who has never
  /// used a 3D viewer.
  static const String hint =
      'Drag to turn. Two fingers or right-drag to move. Pinch or scroll to '
      'zoom.';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final status = statusLabel;
    final size = mesh.size;
    final onUnitChanged = this.onUnitChanged;
    final onPrintBedChanged = this.onPrintBedChanged;
    final bed = printBed;
    final strong = TextStyle(fontSize: 12, color: tokens.foreground);
    final muted = TextStyle(fontSize: 12, color: tokens.mutedForeground);
    // A length, an area or a volume, with the unit raised to [power].
    String measure(double value, [String power = '']) => unit.symbol.isEmpty
        ? formatModelLength(value)
        : '${formatModelLength(value)} ${unit.symbol}$power';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingMd,
          vertical: tokens.spacingSm,
        ),
        child: Wrap(
          spacing: tokens.spacingLg,
          runSpacing: tokens.spacingXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'X ${formatModelLength(size.x)} · '
              'Y ${formatModelLength(size.y)} · '
              'Z ${measure(size.z)}',
              key: const ValueKey('model_viewer_size'),
              style: strong,
            ),
            Text(
              'Area ${measure(measurements.surfaceArea, '²')}',
              key: const ValueKey('model_viewer_area'),
              style: strong,
            ),
            Text(
              measurements.isClosed
                  ? 'Volume ${measure(measurements.volume, '³')}'
                  : 'Volume ≈ ${measure(measurements.volume, '³')}, '
                        'mesh is open',
              key: const ValueKey('model_viewer_volume'),
              style: strong,
            ),
            Text(
              _count(mesh.triangleCount, 'triangle'),
              key: const ValueKey('model_viewer_triangles'),
              style: strong,
            ),
            Text(
              _count(mesh.vertexCount, 'vertex', 'vertices'),
              key: const ValueKey('model_viewer_vertices'),
              style: strong,
            ),
            if (onUnitChanged != null)
              ModelViewerChoiceChip<QuarkModelUnit>(
                keyPrefix: 'model_viewer_unit',
                icon: QuarkIcons.straighten_outlined,
                label: 'Units: ${unit.symbol.isEmpty ? 'file' : unit.symbol}',
                tooltip: 'Units the file is in',
                options: [
                  for (final unit in QuarkModelUnit.values)
                    (id: unit.name, label: unit.label, value: unit),
                ],
                selected: unit,
                onChanged: onUnitChanged,
              ),
            if (onPrintBedChanged != null)
              ModelViewerChoiceChip<QuarkPrintBed?>(
                keyPrefix: 'model_viewer_bed',
                icon: QuarkIcons.print_outlined,
                label: 'Bed: ${bed?.name ?? 'none'}',
                tooltip: 'Check the fit on a print bed',
                options: [
                  (id: 'none', label: 'No bed', value: null),
                  for (final bed in printBeds)
                    (id: bed.id, label: bed.name, value: bed),
                ],
                selected: bed,
                onChanged: onPrintBedChanged,
              ),
            if (bed != null)
              Text(
                '${_fits(bed) ? 'Fits' : 'Too big for'} ${bed.name}'
                '${unit == QuarkModelUnit.file ? ' if in mm' : ''}',
                key: const ValueKey('model_viewer_bed_fit'),
                style: strong,
              ),
            if (status != null)
              Text(
                status,
                key: const ValueKey('model_viewer_status'),
                style: muted,
              ),
            Text(hint, key: const ValueKey('model_viewer_hint'), style: muted),
          ],
        ),
      ),
    );
  }

  /// Whether [mesh], in [unit], fits on [bed].
  bool _fits(QuarkPrintBed bed) {
    final box = mesh.footprint;
    final mm = unit.inMillimeters;
    return bed.fits(
      width: box.width * mm,
      depth: box.depth * mm,
      height: box.height * mm,
    );
  }
}

/// [value] with at most three significant decimals and no trailing zeros:
/// `120`, `45.25`, `0.125`.
String formatModelLength(double value) {
  final magnitude = value.abs();
  final decimals = magnitude >= 100
      ? 1
      : magnitude >= 1
      ? 2
      : 3;
  var text = value.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

String _count(int count, String one, [String? many]) {
  final digits = count.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '$grouped ${count == 1 ? one : many ?? '${one}s'}';
}
