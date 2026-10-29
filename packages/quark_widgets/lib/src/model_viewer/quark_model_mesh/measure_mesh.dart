import 'dart:math' as math;
import 'dart:typed_data';

import '../quark_model_measurements.dart';
import '../quark_model_mesh.dart';

/// [mesh]'s volume, surface area and whether it is closed, for
/// `QuarkModelMesh.measure`.
///
/// The tetrahedra are taken against the middle of the bounding box rather
/// than the origin, so a model far from the origin does not lose its
/// volume to rounding. The closed check welds vertices at the same
/// position first, since OBJ, PLY and glTF files repeat a corner wherever
/// its normal or texture changes, then files every edge under its lower
/// vertex with a counting sort and checks that each one is run along as
/// many times one way as the other. That costs a word per vertex for the
/// weld, two for its table, two more for where each vertex's edges start,
/// and one per triangle corner for the edges.
QuarkModelMeasurements measureMesh(QuarkModelMesh mesh) {
  final positions = mesh.positions;
  final indices = mesh.indices;
  final ox = (mesh.min[0] + mesh.max[0]) / 2;
  final oy = (mesh.min[1] + mesh.max[1]) / 2;
  final oz = (mesh.min[2] + mesh.max[2]) / 2;
  var volume = 0.0, area = 0.0;
  for (var t = 0; t < indices.length; t += 3) {
    final a = indices[t] * 3, b = indices[t + 1] * 3, c = indices[t + 2] * 3;
    final ax = positions[a] - ox;
    final ay = positions[a + 1] - oy;
    final az = positions[a + 2] - oz;
    final bx = positions[b] - ox;
    final by = positions[b + 1] - oy;
    final bz = positions[b + 2] - oz;
    final cx = positions[c] - ox;
    final cy = positions[c + 1] - oy;
    final cz = positions[c + 2] - oz;
    // a · (b × c) is six times the signed tetrahedron's volume.
    volume +=
        ax * (by * cz - bz * cy) +
        ay * (bz * cx - bx * cz) +
        az * (bx * cy - by * cx);
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final vx = cx - ax, vy = cy - ay, vz = cz - az;
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    area += math.sqrt(nx * nx + ny * ny + nz * nz);
  }
  return QuarkModelMeasurements(
    volume: volume.abs() / 6,
    surfaceArea: area / 2,
    isClosed: _isClosed(mesh),
  );
}

/// Whether every edge of [mesh], with its vertices welded, is run along as
/// many times one way as the other.
bool _isClosed(QuarkModelMesh mesh) {
  final indices = mesh.indices;
  if (indices.isEmpty) return false;
  final welded = _weld(mesh.positions);
  // Where each vertex's edges start in [edges]: first a count of the edges
  // whose lower vertex it is, then their running total.
  final starts = Int32List(mesh.vertexCount + 1);
  void corners(void Function(int low, int high, int forward) edge) {
    for (var t = 0; t < indices.length; t += 3) {
      for (var k = 0; k < 3; k++) {
        final from = welded[indices[t + k]];
        final to = welded[indices[t + (k + 1) % 3]];
        // A collapsed edge bounds nothing.
        if (from == to) continue;
        from < to ? edge(from, to, 1) : edge(to, from, 0);
      }
    }
  }

  corners((low, high, forward) => starts[low + 1]++);
  for (var v = 1; v < starts.length; v++) {
    starts[v] += starts[v - 1];
  }
  // The other end of each edge, doubled, plus one when it runs from the
  // lower vertex: under 2^31 for any mesh the viewer will load.
  final edges = Int32List(starts.last);
  final filled = Int32List.fromList(starts);
  corners((low, high, forward) => edges[filled[low]++] = high * 2 + forward);
  for (var v = 0; v + 1 < starts.length; v++) {
    final run = Int32List.sublistView(edges, starts[v], starts[v + 1]);
    if (run.isEmpty) continue;
    _sort(run);
    var balance = 0;
    for (var i = 0; i < run.length; i++) {
      balance += run[i].isOdd ? 1 : -1;
      final last = i + 1 == run.length || run[i + 1] ~/ 2 != run[i] ~/ 2;
      if (last && balance != 0) return false;
      if (last) balance = 0;
    }
  }
  return true;
}

/// Sorts [run] in place: by insertion for the handful of edges most
/// vertices have, so the sort's own setup does not dominate.
void _sort(Int32List run) {
  if (run.length > 16) {
    run.sort();
    return;
  }
  for (var i = 1; i < run.length; i++) {
    final value = run[i];
    var j = i - 1;
    for (; j >= 0 && run[j] > value; j--) {
      run[j + 1] = run[j];
    }
    run[j + 1] = value;
  }
}

/// For each vertex in [positions], the first vertex at the same position,
/// found through an open-addressing table on the coordinates' float bits.
Int32List _weld(Float32List positions) {
  final count = positions.length ~/ 3;
  final bits = Uint32List.view(
    positions.buffer,
    positions.offsetInBytes,
    positions.length,
  );
  var size = 16;
  while (size < count * 2) {
    size *= 2;
  }
  final mask = size - 1;
  final table = Int32List(size)..fillRange(0, size, -1);
  final welded = Int32List(count);
  for (var v = 0; v < count; v++) {
    final at = v * 3;
    var slot = _hash(bits, at) & mask;
    while (true) {
      final existing = table[slot];
      if (existing < 0) {
        table[slot] = v;
        welded[v] = v;
        break;
      }
      final other = existing * 3;
      if (positions[other] == positions[at] &&
          positions[other + 1] == positions[at + 1] &&
          positions[other + 2] == positions[at + 2]) {
        welded[v] = existing;
        break;
      }
      slot = (slot + 1) & mask;
    }
  }
  return welded;
}

// The same hash `MeshBuilder.weld` uses: every product stays under 2^53, so
// it is the same on the web. Negative zero hashes as zero, since it compares
// equal to it.
int _hash(Uint32List bits, int at) {
  var h = 0;
  for (var i = at; i < at + 3; i++) {
    final word = bits[i] == 0x80000000 ? 0 : bits[i];
    h = (h * 31 + (word & 0xffff)) & 0x0fffffff;
    h = (h * 31 + (word >> 16)) & 0x0fffffff;
  }
  h ^= h >> 13;
  h = (h * 0x5bd1) & 0x0fffffff;
  return h ^ (h >> 15);
}
