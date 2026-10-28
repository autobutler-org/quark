import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/model_viewer_service.dart';
import 'package:quark/utils/model_viewer_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A binary PLY sheet of [side] x [side] vertices, 2 (side - 1)² triangles,
/// indexed the way a scanner writes one: 12 bytes a vertex, 13 a triangle.
Uint8List plySheet(int side) {
  final triangles = 2 * (side - 1) * (side - 1);
  final header = ascii.encode(
    'ply\nformat binary_little_endian 1.0\n'
    'element vertex ${side * side}\n'
    'property float x\nproperty float y\nproperty float z\n'
    'element face $triangles\n'
    'property list uchar int vertex_indices\nend_header\n',
  );
  final bytes = Uint8List(header.length + side * side * 12 + triangles * 13)
    ..setAll(0, header);
  final data = ByteData.sublistView(bytes);
  var at = header.length;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      data
        ..setFloat32(at, x / side, Endian.little)
        ..setFloat32(at + 4, y / side, Endian.little)
        ..setFloat32(at + 8, (x * y % 7) / (7 * side), Endian.little);
      at += 12;
    }
  }
  void face(int a, int b, int c) {
    data
      ..setUint8(at, 3)
      ..setInt32(at + 1, a, Endian.little)
      ..setInt32(at + 5, b, Endian.little)
      ..setInt32(at + 9, c, Endian.little);
    at += 13;
  }

  for (var y = 0; y < side - 1; y++) {
    for (var x = 0; x < side - 1; x++) {
      final a = y * side + x;
      face(a, a + 1, a + side);
      face(a + 1, a + side + 1, a + side);
    }
  }
  return bytes;
}

/// `ModelViewerService.parse` with the viewer's own limits (#3231): a model
/// past the old 500,000-triangle cap loads, with a bounded preview, and one
/// past the new cap is refused before its triangles are read.
void main() {
  test('a model over the old cap loads with a preview', () async {
    // 1,201,250 triangles, past the old cap of 500,000.
    final file = plySheet(776);
    final mesh = await ModelViewerService.parse(
      file,
      QuarkModelFormat.ply,
      ModelViewerConfig.limits,
    );
    expect(mesh.triangleCount, 1201250);
    expect(mesh.triangleCount, greaterThan(500000));
    expect(
      mesh.triangleCount,
      lessThanOrEqualTo(ModelViewerConfig.maxTriangles),
    );
    final preview = mesh.preview!;
    expect(
      preview.triangleCount,
      lessThanOrEqualTo(ModelViewerConfig.previewTriangles),
    );
    expect(preview.triangleCount, greaterThan(0));
  });

  test(
    'the parsed mesh holds no more memory than its triangles need',
    () async {
      final file = plySheet(776);
      final mesh = await ModelViewerService.parse(
        file,
        QuarkModelFormat.ply,
        ModelViewerConfig.limits,
      );
      // Exactly 12 bytes a vertex and 24 a triangle, none of the parser's
      // spare capacity: the builder's doubled buffers are not kept.
      expect(mesh.positions.buffer.lengthInBytes, mesh.vertexCount * 12);
      expect(mesh.indices.buffer.lengthInBytes, mesh.triangleCount * 12);
      expect(mesh.normals.buffer.lengthInBytes, mesh.triangleCount * 12);
      final preview = mesh.preview!;
      final previewBytes =
          preview.positions.lengthInBytes +
          preview.indices.lengthInBytes +
          preview.normals.lengthInBytes;
      expect(
        previewBytes,
        lessThanOrEqualTo(ModelViewerConfig.previewTriangles * (3 * 12 + 24)),
      );
    },
  );

  test('a model within the preview budget gets no preview', () async {
    final mesh = await ModelViewerService.parse(
      plySheet(20),
      QuarkModelFormat.ply,
      ModelViewerConfig.limits,
    );
    expect(mesh.preview, isNull);
  });

  test('a parsed model carries its measurements', () async {
    final mesh = await ModelViewerService.parse(
      plySheet(20),
      QuarkModelFormat.ply,
      ModelViewerConfig.limits,
    );
    // A sheet has an edge all round, so it is open.
    expect(mesh.measurements, mesh.measure());
    expect(mesh.measurements!.isClosed, isFalse);
    expect(mesh.measurements!.surfaceArea, greaterThan(0));
  });

  test('a model over the new cap is refused as too detailed', () async {
    const faces = ModelViewerConfig.maxTriangles + 1;
    final header = ascii.encode(
      'ply\nformat binary_little_endian 1.0\n'
      'element vertex 3\n'
      'property float x\nproperty float y\nproperty float z\n'
      'element face $faces\n'
      'property list uchar int vertex_indices\nend_header\n',
    );
    // As long as the count claims, so the header is not dismissed as a lie.
    final file = Uint8List(header.length + faces)..setAll(0, header);
    await expectLater(
      ModelViewerService.parse(
        file,
        QuarkModelFormat.ply,
        ModelViewerConfig.limits,
      ),
      throwsA(
        isA<QuarkModelParseException>().having(
          (e) => e.issue,
          'issue',
          QuarkModelParseIssue.tooManyTriangles,
        ),
      ),
    );
  });
}
