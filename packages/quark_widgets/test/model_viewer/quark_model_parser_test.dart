import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A binary STL of [triangles], each nine floats, after an 80-byte [header].
Uint8List binaryStl(List<List<double>> triangles, {String header = ''}) {
  final data = ByteData(84 + triangles.length * 50);
  final headerBytes = ascii.encode(header);
  for (var i = 0; i < headerBytes.length && i < 80; i++) {
    data.setUint8(i, headerBytes[i]);
  }
  data.setUint32(80, triangles.length, Endian.little);
  for (var t = 0; t < triangles.length; t++) {
    for (var f = 0; f < 9; f++) {
      data.setFloat32(84 + t * 50 + 12 + f * 4, triangles[t][f], Endian.little);
    }
  }
  return data.buffer.asUint8List();
}

/// The unit square in the XY plane as two triangles sharing an edge.
const List<List<double>> square = [
  [0, 0, 0, 1, 0, 0, 1, 1, 0],
  [0, 0, 0, 1, 1, 0, 0, 1, 0],
];

Uint8List text(String source) => Uint8List.fromList(utf8.encode(source));

QuarkModelParseIssue? issueOf(
  Uint8List bytes,
  QuarkModelFormat format, [
  QuarkModelLimits limits = const QuarkModelLimits(),
]) {
  try {
    parseQuarkModel(bytes, format, limits: limits);
    return null;
  } on QuarkModelParseException catch (e) {
    return e.issue;
  }
}

/// A PLY header past the format line: a quad with extra properties and an
/// extra element to read past.
const plyHeader =
    'element vertex 4\n'
    'property float x\n'
    'property float y\n'
    'property float z\n'
    'property uchar red\n'
    'element face 1\n'
    'property list uchar int vertex_indices\n'
    'property int flags\n'
    'element edge 1\n'
    'property int vertex1\n'
    'property int vertex2\n'
    'end_header\n';

/// The [plyHeader] quad in binary, in [endian] byte order.
Uint8List binaryPly(Endian endian) {
  final head = ascii.encode(
    'ply\nformat binary_${endian == Endian.little ? 'little' : 'big'}'
    '_endian 1.0\ncomment made by hand\n$plyHeader',
  );
  final body = ByteData(4 * 13 + 1 + 16 + 4 + 8);
  var at = 0;
  for (final (x, y, z) in [(0, 0, 0), (2, 0, 0), (2, 1, 0), (0, 1, 5)]) {
    body.setFloat32(at, x.toDouble(), endian);
    body.setFloat32(at + 4, y.toDouble(), endian);
    body.setFloat32(at + 8, z.toDouble(), endian);
    body.setUint8(at + 12, 255);
    at += 13;
  }
  body.setUint8(at++, 4);
  for (final index in [0, 1, 2, 3]) {
    body.setInt32(at, index, endian);
    at += 4;
  }
  body.setInt32(at, 7, endian);
  at += 4;
  body.setInt32(at, 0, endian);
  body.setInt32(at + 4, 1, endian);
  return Uint8List.fromList([...head, ...body.buffer.asUint8List()]);
}

/// `parseQuarkModel` (#2988): STL in both encodings, OBJ and PLY in all
/// three, and every cap a file can run into.
void main() {
  group('STL', () {
    test('binary: corners shared between triangles are merged', () {
      final mesh = parseQuarkModel(binaryStl(square), QuarkModelFormat.stl);
      expect(mesh.triangleCount, 2);
      expect(mesh.vertexCount, 4);
      expect(mesh.isZUp, isTrue);
      expect(mesh.size, (x: 1.0, y: 1.0, z: 0.0));
      // Both triangles face +Z.
      expect(mesh.normals.sublist(0, 3), [0, 0, 1]);
      expect(mesh.normals.sublist(3, 6), [0, 0, 1]);
    });

    test('binary whose header starts with "solid" is still binary', () {
      final mesh = parseQuarkModel(
        binaryStl(square, header: 'solid exported by a CAD tool'),
        QuarkModelFormat.stl,
      );
      expect(mesh.triangleCount, 2);
    });

    test('ASCII, with exponents, CRLF line ends and two solids', () {
      final mesh = parseQuarkModel(
        text(
          'solid a\r\n'
          ' facet normal 0 0 1\r\n'
          '  outer loop\r\n'
          '   vertex 0 0 0\r\n'
          '   vertex 1e1 0 0\r\n'
          '   vertex 10.0 -2.5E+0 0\r\n'
          '  endloop\r\n'
          ' endfacet\r\n'
          'endsolid a\r\n'
          'solid b\n'
          'facet normal 0 0 1 outer loop vertex 0 0 1 vertex 1 0 1 '
          'vertex 0 1 1 endloop endfacet\n'
          'endsolid b\n',
        ),
        QuarkModelFormat.stl,
      );
      expect(mesh.triangleCount, 2);
      expect(mesh.vertexCount, 6);
      expect(mesh.size, (x: 10.0, y: 3.5, z: 1.0));
    });
  });

  group('OBJ', () {
    test(
      'polygons become fans; normals, textures and comments are skipped',
      () {
        final mesh = parseQuarkModel(
          text(
            '# a quad and a triangle\n'
            'mtllib quad.mtl\n'
            'o quad\n'
            'v 0 0 0\n'
            'v 2 0 0\n'
            'v 2 3 0\n'
            'v 0 3 0 1.0\n'
            'vt 0 0\n'
            'vn 0 0 1\n'
            'usemtl red\n'
            's off\n'
            'f 1/1/1 2/1/1 3/1/1 4/1/1 # trailing comment\n'
            '  v 0 0 4\n'
            'f -4//1 -3//1 -1//1\n'
            'l 1 2\n',
          ),
          QuarkModelFormat.obj,
        );
        expect(mesh.triangleCount, 3);
        expect(mesh.vertexCount, 5);
        expect(mesh.isZUp, isFalse);
        expect(mesh.size, (x: 2.0, y: 3.0, z: 4.0));
        expect(mesh.indices, [0, 1, 2, 0, 2, 3, 1, 2, 4]);
      },
    );

    test('index 0, one past the end, or garbage is malformed', () {
      for (final face in ['f 0 1 2', 'f 1 2 4', 'f 1 2 x', 'f -4 1 2']) {
        expect(
          issueOf(
            text('v 0 0 0\nv 1 0 0\nv 0 1 0\n$face\n'),
            QuarkModelFormat.obj,
          ),
          QuarkModelParseIssue.malformed,
          reason: face,
        );
      }
    });
  });

  group('PLY', () {
    void expectQuad(QuarkModelMesh mesh) {
      expect(mesh.triangleCount, 2);
      expect(mesh.vertexCount, 4);
      expect(mesh.size, (x: 2.0, y: 1.0, z: 5.0));
      expect(mesh.indices, [0, 1, 2, 0, 2, 3]);
    }

    test('ASCII, with extra properties and elements read past', () {
      expectQuad(
        parseQuarkModel(
          text(
            'ply\r\nformat ascii 1.0\r\n'
            '${plyHeader.replaceAll('\n', '\r\n')}'
            '0 0 0 255\n2 0 0 255\n2 1 0 255\n0 1 5 255\n'
            '4 0 1 2 3 7\n'
            '0 1\n',
          ),
          QuarkModelFormat.ply,
        ),
      );
    });

    for (final endian in [Endian.little, Endian.big]) {
      test('binary ${endian == Endian.little ? 'little' : 'big'}-endian', () {
        expectQuad(parseQuarkModel(binaryPly(endian), QuarkModelFormat.ply));
      });
    }

    test('no magic, no format, or an unknown type is malformed', () {
      for (final source in [
        'not a ply\n',
        'ply\nelement vertex 0\nend_header\n',
        'ply\nformat ascii 1.0\nelement vertex 1\nproperty quad x\n'
            'end_header\n',
        'ply\nformat ascii 1.0\nelement vertex 1\nproperty float y\n'
            'end_header\n1\n',
      ]) {
        expect(
          issueOf(text(source), QuarkModelFormat.ply),
          QuarkModelParseIssue.malformed,
          reason: source,
        );
      }
    });
  });

  group('bytes and limits give an issue', () {
    final stl = binaryStl(square);
    final ply = binaryPly(Endian.little);
    const facet = 'outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endloop\n';
    for (final (description, bytes, format, limits, issue)
        in <
          (
            String,
            Uint8List,
            QuarkModelFormat,
            QuarkModelLimits,
            QuarkModelParseIssue,
          )
        >[
          (
            'STL: a binary file shorter than its triangle count is malformed',
            Uint8List.sublistView(stl, 0, stl.length - 10),
            QuarkModelFormat.stl,
            const QuarkModelLimits(),
            QuarkModelParseIssue.malformed,
          ),
          (
            'STL: text that is no solid is malformed',
            text('hello'),
            QuarkModelFormat.stl,
            const QuarkModelLimits(),
            QuarkModelParseIssue.malformed,
          ),
          (
            'STL: a vertex that is not a number is malformed',
            text('solid x\nouter loop\nvertex 0 zero 0\n endloop\n endsolid'),
            QuarkModelFormat.stl,
            const QuarkModelLimits(),
            QuarkModelParseIssue.malformed,
          ),
          (
            'STL: an empty solid has no surfaces',
            text('solid empty\n endsolid empty\n'),
            QuarkModelFormat.stl,
            const QuarkModelLimits(),
            QuarkModelParseIssue.noSurfaces,
          ),
          (
            'STL: a binary count over the cap is refused before it is read',
            stl,
            QuarkModelFormat.stl,
            const QuarkModelLimits(maxTriangles: 1),
            QuarkModelParseIssue.tooManyTriangles,
          ),
          (
            'STL: an ASCII file over the triangle cap stops there',
            text('solid x\n${facet * 3}endsolid'),
            QuarkModelFormat.stl,
            const QuarkModelLimits(maxTriangles: 2),
            QuarkModelParseIssue.tooManyTriangles,
          ),
          (
            'STL: reading past the time cap gives up',
            text('solid x\n${facet * 5000}endsolid'),
            QuarkModelFormat.stl,
            const QuarkModelLimits(maxDuration: Duration.zero),
            QuarkModelParseIssue.tooSlow,
          ),
          (
            'a file over the size cap is refused before it is parsed',
            stl,
            QuarkModelFormat.stl,
            const QuarkModelLimits(maxBytes: 100),
            QuarkModelParseIssue.tooLarge,
          ),
          (
            'OBJ: vertices without faces have no surfaces',
            text('v 0 0 0\nv 1 1 1\n'),
            QuarkModelFormat.obj,
            const QuarkModelLimits(),
            QuarkModelParseIssue.noSurfaces,
          ),
          (
            'OBJ: more vertices than the cap allows stops there',
            text('v 0 0 0\n' * 10),
            QuarkModelFormat.obj,
            const QuarkModelLimits(maxTriangles: 2),
            QuarkModelParseIssue.tooManyTriangles,
          ),
          (
            'PLY: a body shorter than the header promises is malformed',
            Uint8List.sublistView(ply, 0, ply.length - 20),
            QuarkModelFormat.ply,
            const QuarkModelLimits(),
            QuarkModelParseIssue.malformed,
          ),
          (
            'PLY: a point cloud has no surfaces',
            text(
              'ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\n'
              'property float y\nproperty float z\nend_header\n1 2 3\n',
            ),
            QuarkModelFormat.ply,
            const QuarkModelLimits(),
            QuarkModelParseIssue.noSurfaces,
          ),
          (
            'PLY: a declared face count over the cap is refused up front',
            ply,
            QuarkModelFormat.ply,
            const QuarkModelLimits(maxTriangles: 0),
            QuarkModelParseIssue.tooManyTriangles,
          ),
        ]) {
      test(description, () {
        expect(issueOf(bytes, format, limits), issue);
      });
    }
  });
}
