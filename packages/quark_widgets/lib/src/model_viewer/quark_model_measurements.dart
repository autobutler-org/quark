import 'package:flutter/foundation.dart';

/// What a `QuarkModelMesh` measures (#3228), in the file's units:
/// [surfaceArea] in square units, [volume] in cubic ones.
///
/// [volume] is the sum of the signed tetrahedra each triangle makes with a
/// fixed point, which is the enclosed volume only when the surface is
/// closed: every edge one triangle runs along one way, another runs along
/// the other way. [isClosed] says whether it is; for an open mesh (a hole,
/// a missing face, a triangle facing the wrong way) [volume] is a rough
/// estimate at best.
///
/// ```dart
/// final measurements = mesh.measurements ?? mesh.measure();
/// ```
@immutable
class QuarkModelMeasurements {
  /// Creates the measurements; `QuarkModelMesh.measure` makes them.
  const QuarkModelMeasurements({
    required this.volume,
    required this.surfaceArea,
    required this.isClosed,
  });

  /// The enclosed volume, never negative: a mesh whose triangles all face
  /// inward measures the same as one facing out.
  final double volume;

  /// The total area of every triangle.
  final double surfaceArea;

  /// Whether the surface is closed, so [volume] is the enclosed volume.
  final bool isClosed;

  @override
  bool operator ==(Object other) =>
      other is QuarkModelMeasurements &&
      other.volume == volume &&
      other.surfaceArea == surfaceArea &&
      other.isClosed == isClosed;

  @override
  int get hashCode => Object.hash(volume, surfaceArea, isClosed);
}
