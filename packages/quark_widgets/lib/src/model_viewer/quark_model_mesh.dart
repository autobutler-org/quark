import 'dart:math' as math;
import 'dart:typed_data';

import 'quark_model_measurements.dart';
import 'quark_model_mesh/cluster_vertices.dart';
import 'quark_model_mesh/measure_mesh.dart';

/// The 3D file formats `parseQuarkModel` reads.
enum QuarkModelFormat {
  /// STereoLithography, ASCII or binary. Its files are Z-up by convention,
  /// the way 3D printers and slicers lay them out.
  stl,

  /// Wavefront OBJ: positions and faces; normals, texture coordinates and
  /// materials are ignored. Y-up by convention.
  obj,

  /// Stanford PLY, ASCII or binary of either byte order: the `vertex`
  /// element's `x`, `y`, `z` and the `face` element's index list. Y-up by
  /// convention.
  ply,

  /// glTF 2.0, JSON (`.gltf`) or binary (`.glb`): the triangles of every
  /// mesh in the default scene, placed by their nodes' transforms. Y-up, as
  /// the format specifies.
  gltf,

  /// 3D Manufacturing Format (`.3mf`): a zip package whose XML model part
  /// lists each object's vertices and triangles, and the build items that
  /// place them. Z-up, as the format specifies.
  threeMf;

  /// Whether the format's files put Z up rather than Y.
  bool get isZUp => this == stl || this == threeMf;
}

/// A triangle mesh ready to draw: shared vertex [positions], [indices] naming
/// three vertices per triangle, and one unit normal per triangle.
///
/// The coordinates are the file's own, in whatever unit it was written in;
/// [isZUp] says which axis the viewer should treat as up. Every field is a
/// typed list, so a mesh crosses an isolate boundary as plain data.
///
/// A mesh too detailed to turn smoothly can carry a [preview], a coarser
/// copy `QuarkModelViewer` draws while the model is moving (#3231);
/// [withPreview] makes one, and is worth running on the isolate that parsed
/// the mesh. It can carry its [measurements] the same way (#3228), made by
/// [withMeasurements] where the mesh was parsed, since measuring a detailed
/// mesh takes a while.
///
/// ```dart
/// final mesh = QuarkModelMesh.fromTriangles(
///   positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
///   indices: Uint32List.fromList([0, 1, 2]),
/// );
/// ```
class QuarkModelMesh {
  /// Creates a mesh from its parts. [fromTriangles] computes [normals] and
  /// the bounds; use this one only to rebuild a mesh already made.
  const QuarkModelMesh({
    required this.positions,
    required this.indices,
    required this.normals,
    required this.min,
    required this.max,
    this.isZUp = false,
    this.preview,
    this.measurements,
  });

  /// Builds a mesh from [positions] (x, y, z per vertex) and [indices]
  /// (three per triangle), computing face normals and the bounding box. A
  /// degenerate triangle gets a zero normal.
  factory QuarkModelMesh.fromTriangles({
    required Float32List positions,
    required Uint32List indices,
    bool isZUp = false,
  }) {
    final normals = Float32List(indices.length);
    for (var t = 0; t < indices.length; t += 3) {
      final a = indices[t] * 3, b = indices[t + 1] * 3, c = indices[t + 2] * 3;
      final ux = positions[b] - positions[a];
      final uy = positions[b + 1] - positions[a + 1];
      final uz = positions[b + 2] - positions[a + 2];
      final vx = positions[c] - positions[a];
      final vy = positions[c + 1] - positions[a + 1];
      final vz = positions[c + 2] - positions[a + 2];
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 0) {
        normals[t] = nx / length;
        normals[t + 1] = ny / length;
        normals[t + 2] = nz / length;
      }
    }
    final min = Float64List(3)..fillRange(0, 3, double.infinity);
    final max = Float64List(3)..fillRange(0, 3, double.negativeInfinity);
    for (var i = 0; i < positions.length; i += 3) {
      for (var axis = 0; axis < 3; axis++) {
        final value = positions[i + axis];
        if (value < min[axis]) min[axis] = value;
        if (value > max[axis]) max[axis] = value;
      }
    }
    if (positions.isEmpty) {
      min.fillRange(0, 3, 0);
      max.fillRange(0, 3, 0);
    }
    return QuarkModelMesh(
      positions: positions,
      indices: indices,
      normals: normals,
      min: min,
      max: max,
      isZUp: isZUp,
    );
  }

  /// x, y, z of every vertex, in the file's units.
  final Float32List positions;

  /// Three vertex numbers per triangle, each an index into [positions] / 3.
  final Uint32List indices;

  /// The unit normal of each triangle, x, y, z, in triangle order.
  final Float32List normals;

  /// The smallest x, y and z of any vertex.
  final Float64List min;

  /// The largest x, y and z of any vertex.
  final Float64List max;

  /// Whether Z is up (STL, 3MF) rather than Y (OBJ, PLY, glTF).
  final bool isZUp;

  /// A coarser copy of this mesh, with the same bounds, drawn in its place
  /// while the model moves; null draws this mesh all the time.
  final QuarkModelMesh? preview;

  /// This mesh's volume, area and whether it is closed, or null when they
  /// have not been measured; [measure] measures them.
  final QuarkModelMeasurements? measurements;

  /// This mesh carrying a [preview] of at most [maxTriangles] triangles, or
  /// carrying none when it already has no more than that.
  ///
  /// The preview merges every vertex inside one cell of a cubic grid over
  /// the bounds into their average and drops the triangles that collapse,
  /// with the grid coarsened until few enough are left. It costs a pass
  /// over the vertices and triangles per grid tried, and the memory of the
  /// preview plus a word per vertex.
  QuarkModelMesh withPreview(int maxTriangles) => _copy(
    preview: triangleCount > maxTriangles
        ? clusterVertices(this, maxTriangles)
        : null,
    measurements: measurements,
  );

  /// This mesh carrying its [measurements], measured once here.
  QuarkModelMesh withMeasurements() =>
      _copy(preview: preview, measurements: measure());

  /// Measures this mesh's volume and surface area, and whether it is closed.
  ///
  /// It costs a pass over the vertices, three over the triangles, and while
  /// it runs about 12 bytes a triangle and 20 a vertex.
  QuarkModelMeasurements measure() => measureMesh(this);

  QuarkModelMesh _copy({
    required QuarkModelMesh? preview,
    required QuarkModelMeasurements? measurements,
  }) => QuarkModelMesh(
    positions: positions,
    indices: indices,
    normals: normals,
    min: min,
    max: max,
    isZUp: isZUp,
    preview: preview,
    measurements: measurements,
  );

  /// How many vertices the mesh has, after identical ones are merged.
  int get vertexCount => positions.length ~/ 3;

  /// How many triangles the mesh has, after polygons are split into them.
  int get triangleCount => indices.length ~/ 3;

  /// Whether there is nothing to draw.
  bool get isEmpty => indices.isEmpty;

  /// The bounding box's size along x, y and z, in the file's units.
  ({double x, double y, double z}) get size =>
      (x: max[0] - min[0], y: max[1] - min[1], z: max[2] - min[2]);

  /// The bounding box as it stands on a print bed, in the file's units:
  /// [width] and [depth] across, [height] along the up axis [isZUp] names.
  ({double width, double depth, double height}) get footprint {
    final size = this.size;
    return isZUp
        ? (width: size.x, depth: size.y, height: size.z)
        : (width: size.x, depth: size.z, height: size.y);
  }
}
