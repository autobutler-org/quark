import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'quark_model_viewer_test.dart' show box;

/// [mesh] with every triangle's winding reversed, so every normal faces in.
QuarkModelMesh flipped(QuarkModelMesh mesh) {
  final indices = Uint32List.fromList(mesh.indices);
  for (var t = 0; t < indices.length; t += 3) {
    final b = indices[t + 1];
    indices[t + 1] = indices[t + 2];
    indices[t + 2] = b;
  }
  return QuarkModelMesh.fromTriangles(
    positions: mesh.positions,
    indices: indices,
  );
}

/// [mesh] with its corners copied once per triangle, the way a glTF file
/// with flat normals repeats every corner.
QuarkModelMesh unwelded(QuarkModelMesh mesh) {
  final positions = Float32List(mesh.indices.length * 3);
  for (var i = 0; i < mesh.indices.length; i++) {
    positions.setRange(i * 3, i * 3 + 3, mesh.positions, mesh.indices[i] * 3);
  }
  return QuarkModelMesh.fromTriangles(
    positions: positions,
    indices: Uint32List.fromList([
      for (var i = 0; i < mesh.indices.length; i++) i,
    ]),
  );
}

/// [mesh] moved by [offset] along every axis.
QuarkModelMesh moved(QuarkModelMesh mesh, double offset) =>
    QuarkModelMesh.fromTriangles(
      positions: Float32List.fromList([
        for (final value in mesh.positions) value + offset,
      ]),
      indices: mesh.indices,
    );

/// `QuarkModelMesh.measure` (#3228): volume, area, and whether the surface
/// is closed.
void main() {
  test('a closed box measures its volume and area', () {
    final measurements = box().measure();
    expect(measurements.isClosed, isTrue);
    expect(measurements.volume, closeTo(24, 1e-9));
    expect(measurements.surfaceArea, closeTo(52, 1e-9));
  });

  test('a box facing inward measures the same', () {
    final measurements = flipped(box()).measure();
    expect(measurements.isClosed, isTrue);
    expect(measurements.volume, closeTo(24, 1e-9));
  });

  test('a box missing a face is open', () {
    final full = box();
    final open = QuarkModelMesh.fromTriangles(
      positions: full.positions,
      indices: Uint32List.sublistView(full.indices, 6),
    );
    final measurements = open.measure();
    expect(measurements.isClosed, isFalse);
    expect(measurements.surfaceArea, closeTo(52 - 6, 1e-9));
  });

  test('one triangle facing the wrong way leaves the surface open', () {
    final full = box();
    final indices = Uint32List.fromList(full.indices);
    final b = indices[1];
    indices[1] = indices[2];
    indices[2] = b;
    final measurements = QuarkModelMesh.fromTriangles(
      positions: full.positions,
      indices: indices,
    ).measure();
    expect(measurements.isClosed, isFalse);
  });

  test('corners repeated per triangle still make a closed box', () {
    final measurements = unwelded(box()).measure();
    expect(measurements.isClosed, isTrue);
    expect(measurements.volume, closeTo(24, 1e-9));
  });

  test('a vertex with many edges is checked like any other', () {
    // Two apexes, vertices 0 and 1, over a ring of [sides]: each apex is
    // the lower end of all its edges.
    const sides = 40;
    final positions = Float32List.fromList([
      0, 0, 1, 0, 0, -1, //
      for (var i = 0; i < sides; i++) ...[
        math.cos(2 * math.pi * i / sides),
        math.sin(2 * math.pi * i / sides),
        0,
      ],
    ]);
    final indices = Uint32List.fromList([
      for (var i = 0; i < sides; i++) ...[
        0,
        2 + i,
        2 + (i + 1) % sides,
        1,
        2 + (i + 1) % sides,
        2 + i,
      ],
    ]);
    final measurements = QuarkModelMesh.fromTriangles(
      positions: positions,
      indices: indices,
    ).measure();
    expect(measurements.isClosed, isTrue);
    // Two cones of height one on a regular polygon of radius one.
    final base = sides / 2 * math.sin(2 * math.pi / sides);
    expect(measurements.volume, closeTo(2 * base / 3, 1e-6));

    final open = QuarkModelMesh.fromTriangles(
      positions: positions,
      indices: Uint32List.sublistView(indices, 3),
    ).measure();
    expect(open.isClosed, isFalse);
  });

  test('a box far from the origin keeps its volume', () {
    final measurements = moved(box(), 100000).measure();
    expect(measurements.volume, closeTo(24, 1e-6));
    expect(measurements.isClosed, isTrue);
  });

  test('withMeasurements and withPreview keep each other', () {
    final mesh = box().withMeasurements();
    expect(mesh.measurements, box().measure());
    final previewed = mesh.withPreview(1);
    expect(previewed.preview, isNotNull);
    expect(previewed.measurements, mesh.measurements);
    expect(previewed.withMeasurements().preview, same(previewed.preview));
  });

  test('the footprint stands on the up axis', () {
    expect(box().footprint, (width: 2, depth: 3, height: 4));
    expect(box(isZUp: false).footprint, (width: 2, depth: 4, height: 3));
  });
}
