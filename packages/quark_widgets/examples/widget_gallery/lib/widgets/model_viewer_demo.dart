import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A torus written out as an OBJ file and read back with `parseQuarkModel`,
/// so the gallery shows the parser and the viewer together. The demo keeps
/// the wireframe flag, the unit and the print bed the viewer leaves to its
/// caller, and logs each change.
class ModelViewerDemo extends StatefulWidget {
  /// Creates the demo; [log] receives each callback.
  const ModelViewerDemo({required this.log, super.key});

  /// Writes a line to the gallery's event panel.
  final void Function(String message) log;

  @override
  State<ModelViewerDemo> createState() => _ModelViewerDemoState();
}

class _ModelViewerDemoState extends State<ModelViewerDemo> {
  static final QuarkModelMesh _torus = parseQuarkModel(
    Uint8List.fromList(utf8.encode(_torusObj(48, 24))),
    QuarkModelFormat.obj,
  );

  bool _wireframe = false;
  QuarkModelUnit _unit = QuarkModelUnit.file;
  QuarkPrintBed? _printBed;

  /// An OBJ torus of [rings] by [sides] quads, 40 units across.
  static String _torusObj(int rings, int sides) {
    final obj = StringBuffer('# torus\n');
    for (var r = 0; r < rings; r++) {
      final u = r / rings * 2 * math.pi;
      for (var s = 0; s < sides; s++) {
        final v = s / sides * 2 * math.pi;
        final radius = 14 + 6 * math.cos(v);
        obj.writeln(
          'v ${radius * math.cos(u)} ${6 * math.sin(v)} '
          '${radius * math.sin(u)}',
        );
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < sides; s++) {
        int at(int ring, int side) =>
            (ring % rings) * sides + (side % sides) + 1;
        obj.writeln(
          'f ${at(r, s)} ${at(r, s + 1)} ${at(r + 1, s + 1)} ${at(r + 1, s)}',
        );
      }
    }
    return obj.toString();
  }

  @override
  Widget build(BuildContext context) {
    return QuarkModelViewer(
      mesh: _torus,
      wireframe: _wireframe,
      onWireframeChanged: (wireframe) {
        widget.log('QuarkModelViewer.onWireframeChanged($wireframe)');
        setState(() => _wireframe = wireframe);
      },
      unit: _unit,
      onUnitChanged: (unit) {
        widget.log('QuarkModelViewer.onUnitChanged(${unit.name})');
        setState(() => _unit = unit);
      },
      printBed: _printBed,
      onPrintBedChanged: (bed) {
        widget.log('QuarkModelViewer.onPrintBedChanged(${bed?.id})');
        setState(() => _printBed = bed);
      },
      statusLabel: 'Torus written as OBJ',
    );
  }
}
