import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/controllers/model_viewer_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One triangle, ready-made, for a fake parser to hand back.
final QuarkModelMesh triangle = QuarkModelMesh.fromTriangles(
  positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
  indices: Uint32List.fromList([0, 1, 2]),
);

/// `ModelViewerController` (#2988): what it reads, what it refuses to
/// download, and how each failure surfaces.
void main() {
  late List<({int start, int length})> reads;
  late List<String> paths;
  late List<(int, QuarkModelFormat)> parses;
  late Map<String, Uint8List> parsedResources;
  late List<(String, String?, QuarkModelMesh)> loaded;

  setUp(() {
    reads = [];
    paths = [];
    parses = [];
    parsedResources = {};
    loaded = [];
  });

  /// A Quark serving [size] bytes, saying how big the file is unless
  /// [reportsSize] is false.
  ReadCodeRangeFn quark(int size, {bool reportsSize = true}) =>
      (path, {required start, required length, serial}) async {
        reads.add((start: start, length: length));
        paths.add(path);
        final end = (start + length).clamp(0, size);
        return (
          bytes: Uint8List(end - start),
          totalSize: reportsSize ? size : null,
        );
      };

  Future<QuarkModelMesh> parseOk(
    Uint8List bytes,
    QuarkModelFormat format,
    QuarkModelLimits limits, {
    Map<String, Uint8List> resources = const {},
  }) async {
    parses.add((bytes.length, format));
    parsedResources = resources;
    return triangle;
  }

  ModelViewerController controller({
    String path = 'prints/part.stl',
    required ReadCodeRangeFn readRange,
    ParseModelFn? parse,
    List<String> resources = const [],
    int maxBytes = 1000,
  }) {
    final controller = ModelViewerController(
      path: path,
      readRange: readRange,
      parse: parse ?? parseOk,
      listResources: (bytes, format) async => resources,
      limits: QuarkModelLimits(maxBytes: maxBytes),
      onMeshLoaded: ({required path, serial, required mesh}) =>
          loaded.add((path, serial, mesh)),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('reads the whole file once its size fits, and parses it', () async {
    final viewer = controller(readRange: quark(500));
    expect(viewer.isLoading, isTrue);
    await viewer.load();
    expect(viewer.isLoading, isFalse);
    expect(viewer.mesh, same(triangle));
    expect(viewer.error, isNull);
    expect(viewer.fallback, isNull);
    expect(viewer.fileSize, 500);
    expect(reads, [(start: 0, length: 1), (start: 0, length: 1001)]);
    expect(parses, [(500, QuarkModelFormat.stl)]);
  });

  test('hands the parsed mesh on for its thumbnail (#3227)', () async {
    final viewer = controller(readRange: quark(500));
    await viewer.load();
    expect(loaded, [('prints/part.stl', null, triangle)]);
  });

  test('a file it falls back on hands nothing on', () async {
    final viewer = controller(
      readRange: quark(500),
      parse: (bytes, format, limits, {resources = const {}}) async =>
          throw const QuarkModelParseException(QuarkModelParseIssue.malformed),
    );
    await viewer.load();
    expect(viewer.fallback, QuarkModelParseIssue.malformed);
    expect(loaded, isEmpty);
  });

  test('a file the Quark says is over the cap is never downloaded', () async {
    final viewer = controller(readRange: quark(5000));
    await viewer.load();
    expect(viewer.fallback, QuarkModelParseIssue.tooLarge);
    expect(viewer.mesh, isNull);
    expect(reads, [(start: 0, length: 1)]);
    expect(parses, isEmpty);
  });

  test('without a size, the read stops one byte past the cap', () async {
    final viewer = controller(readRange: quark(5000, reportsSize: false));
    await viewer.load();
    expect(viewer.fallback, QuarkModelParseIssue.tooLarge);
    expect(reads.last.length, 1001);
    expect(parses, isEmpty);
  });

  test('a file the parser refuses falls back with its reason', () async {
    final viewer = controller(
      path: 'scans/bunny.PLY',
      readRange: quark(10),
      parse: (bytes, format, limits, {resources = const {}}) async {
        parses.add((bytes.length, format));
        throw const QuarkModelParseException(
          QuarkModelParseIssue.tooManyTriangles,
        );
      },
    );
    await viewer.load();
    expect(parses.single.$2, QuarkModelFormat.ply);
    expect(viewer.fallback, QuarkModelParseIssue.tooManyTriangles);
    expect(viewer.error, isNull);
  });

  test('a failed request is an error with Retry, not a fallback', () async {
    var fail = true;
    final viewer = controller(
      readRange: (path, {required start, required length, serial}) async {
        if (fail) throw ApiException(500, 'boom');
        return (bytes: Uint8List(3), totalSize: 3);
      },
    );
    await viewer.load();
    expect(viewer.error, isA<ApiException>());
    expect(viewer.fallback, isNull);
    fail = false;
    await viewer.load();
    expect(viewer.error, isNull);
    expect(viewer.mesh, same(triangle));
  });

  test(
    'a file the viewer has no format for falls back as unreadable',
    () async {
      final viewer = controller(path: 'models/part.fbx', readRange: quark(10));
      await viewer.load();
      expect(viewer.fallback, QuarkModelParseIssue.malformed);
      expect(reads, isEmpty);
    },
  );

  test('a .gltf reads the .bin files it names beside it', () async {
    final viewer = controller(
      path: 'models/car.gltf',
      readRange: quark(300),
      resources: ['car.bin', 'car.bin', 'wheels.bin'],
    );
    await viewer.load();
    expect(viewer.mesh, same(triangle));
    expect(paths, [
      'models/car.gltf',
      'models/car.gltf',
      'models/car.bin',
      'models/wheels.bin',
    ]);
    // Each sibling read stops one byte past what the cap has left.
    expect(reads.sublist(2), [
      (start: 0, length: 701),
      (start: 0, length: 401),
    ]);
    expect(parses, [(300, QuarkModelFormat.gltf)]);
    expect(parsedResources.keys, ['car.bin', 'wheels.bin']);
    expect(parsedResources['wheels.bin'], hasLength(300));
  });

  test('siblings that take the model over the cap fall back', () async {
    final viewer = controller(
      path: 'car.gltf',
      readRange: quark(600),
      resources: ['car.bin'],
    );
    await viewer.load();
    expect(paths.last, 'car.bin');
    expect(viewer.fallback, QuarkModelParseIssue.tooLarge);
    expect(parses, isEmpty);
  });

  test('a missing sibling makes the model unreadable, not an error', () async {
    final viewer = controller(
      path: 'car.gltf',
      readRange: (path, {required start, required length, serial}) async {
        if (path == 'car.bin') throw ApiException(404, 'missing');
        return (bytes: Uint8List(3), totalSize: 3);
      },
      resources: ['car.bin'],
    );
    await viewer.load();
    expect(viewer.fallback, QuarkModelParseIssue.malformed);
    expect(viewer.error, isNull);
  });

  test('only the latest load lands', () async {
    final viewer = controller(readRange: quark(10));
    final first = viewer.load();
    final second = viewer.load();
    await Future.wait([first, second]);
    expect(viewer.mesh, same(triangle));
    expect(parses, hasLength(1));
  });

  test('wireframe toggles and notifies once per change', () {
    final viewer = controller(readRange: quark(10));
    var notified = 0;
    viewer.addListener(() => notified++);
    viewer.setWireframe(true);
    viewer.setWireframe(true);
    expect(viewer.wireframe, isTrue);
    expect(notified, 1);
  });
}
