import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/controllers/model_viewer_controller.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/model_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/model_viewer_config.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// A binary STL of one right triangle, 10 by 20 in the XY plane.
Uint8List triangleStl() {
  final data = ByteData(84 + 50)..setUint32(80, 1, Endian.little);
  const corners = <double>[0, 0, 0, 10, 0, 0, 0, 20, 0];
  for (var i = 0; i < corners.length; i++) {
    data.setFloat32(96 + i * 4, corners[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// The 3D model viewer page (#2988): the model with its counts, the
/// fallback to the file's details, the error with Retry, and leaving.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ReadCodeRangeFn serving(Uint8List bytes) =>
      (path, {required start, required length, serial}) async => (
        bytes: Uint8List.sublistView(
          bytes,
          start.clamp(0, bytes.length),
          (start + length).clamp(0, bytes.length),
        ),
        totalSize: bytes.length,
      );

  Future<GoRouter> pumpViewer(
    WidgetTester tester, {
    ReadCodeRangeFn? readRange,
    String filePath = 'prints/part.stl',
    int maxBytes = 1024,
    QuarkModelLimits? limits,
    Size size = const Size(1280, 800),
  }) async {
    setViewport(tester, size);
    final controller = ModelViewerController(
      path: filePath,
      readRange: readRange ?? serving(triangleStl()),
      // Inline, so the test needs no second isolate.
      parse: (bytes, format, limits, {resources = const {}}) async =>
          parseQuarkModel(bytes, format, limits: limits, resources: resources),
      listResources: (bytes, format) async =>
          quarkModelResources(bytes, format),
      limits: limits ?? QuarkModelLimits(maxBytes: maxBytes),
    );
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.modelViewerPath(filePath),
      routes: [
        GoRoute(
          path: '${AppRoutes.files}/:path(.*)',
          builder: (_, state) =>
              Scaffold(body: Text('folder:${state.pathParameters['path']}')),
        ),
        GoRoute(
          path: '${AppRoutes.modelViewer}/:path(.*)',
          builder: (_, state) => ModelViewerPage(
            filePath: state.pathParameters['path'] ?? '',
            controller: controller,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.from(
          QuarkThemeColor.classic.tokensFor(Brightness.dark),
          Brightness.dark,
        ),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('draws the model with its size at ${size.width}', (
      tester,
    ) async {
      await pumpViewer(tester, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('part.stl'), findsOneWidget);
      expect(find.byType(QuarkModelViewer), findsOneWidget);
      expect(find.text('X 10 · Y 20 · Z 0'), findsOneWidget);
      expect(find.text('1 triangle'), findsOneWidget);
      expect(find.text('3 vertices'), findsOneWidget);
      expect(find.text('STL · 134 B'), findsOneWidget);
    });
  }

  testWidgets('a .gltf draws from the .bin beside it (#3225)', (tester) async {
    // The same triangle, as three float corners in a sibling buffer.
    final bin = Float32List.fromList([0, 0, 0, 10, 0, 0, 0, 20, 0]);
    final gltf = utf8.encode(
      jsonEncode({
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': 36, 'uri': 'tri.bin'},
        ],
        'bufferViews': [
          {'buffer': 0, 'byteLength': 36},
        ],
        'accessors': [
          {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
        ],
        'meshes': [
          {
            'primitives': [
              {
                'attributes': {'POSITION': 0},
              },
            ],
          },
        ],
      }),
    );
    final files = {
      'models/tri.gltf': serving(gltf),
      'models/tri.bin': serving(bin.buffer.asUint8List()),
    };
    await pumpViewer(
      tester,
      filePath: 'models/tri.gltf',
      readRange: (path, {required start, required length, serial}) =>
          files[path]!(path, start: start, length: length, serial: serial),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(QuarkModelViewer), findsOneWidget);
    expect(find.text('X 10 · Y 20 · Z 0'), findsOneWidget);
    expect(find.text('1 triangle'), findsOneWidget);
  });

  testWidgets('the wireframe button reaches the controller', (tester) async {
    await pumpViewer(tester);
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_wireframe_toggle')),
    );
    await tester.pump();
    expect(
      tester.widget<QuarkModelViewer>(find.byType(QuarkModelViewer)).wireframe,
      isTrue,
    );
  });

  testWidgets('the unit and bed chips reach the controller', (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.byKey(const ValueKey('model_viewer_unit')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_unit_option_millimeters')),
    );
    await tester.pumpAndSettle();
    expect(find.text('X 10 · Y 20 · Z 0 mm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model_viewer_bed')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_bed_option_prusa_mini')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fits Prusa MINI'), findsOneWidget);
  });

  testWidgets('a model over the cap falls back to its details and says why', (
    tester,
  ) async {
    await pumpViewer(tester, maxBytes: 100);
    expect(find.byType(QuarkModelViewer), findsNothing);
    expect(find.byType(GenericFileViewerPage), findsOneWidget);
    expect(
      find.text(Errors.modelPreview(QuarkModelParseIssue.tooLarge)),
      findsOneWidget,
    );
  });

  testWidgets('a model over the triangle cap says it is too detailed', (
    tester,
  ) async {
    const faces = ModelViewerConfig.maxTriangles + 1;
    final header = ascii.encode(
      'ply\nformat binary_little_endian 1.0\n'
      'element vertex 3\n'
      'property float x\nproperty float y\nproperty float z\n'
      'element face $faces\n'
      'property list uchar int vertex_indices\nend_header\n',
    );
    await pumpViewer(
      tester,
      filePath: 'scans/statue.ply',
      readRange: serving(Uint8List(header.length + faces)..setAll(0, header)),
      limits: ModelViewerConfig.limits,
    );
    expect(find.byType(QuarkModelViewer), findsNothing);
    expect(find.byType(GenericFileViewerPage), findsOneWidget);
    expect(
      find.text(Errors.modelPreview(QuarkModelParseIssue.tooManyTriangles)),
      findsOneWidget,
    );
  });

  testWidgets('a file that is not a model falls back too', (tester) async {
    await pumpViewer(
      tester,
      filePath: 'scans/broken.obj',
      readRange: serving(Uint8List.fromList('f 1 2 3\n'.codeUnits)),
    );
    expect(find.byType(GenericFileViewerPage), findsOneWidget);
    expect(
      find.text(Errors.modelPreview(QuarkModelParseIssue.malformed)),
      findsOneWidget,
    );
  });

  testWidgets('a refused request shows the error and Retry reloads', (
    tester,
  ) async {
    var fail = true;
    final good = serving(triangleStl());
    await pumpViewer(
      tester,
      readRange: (path, {required start, required length, serial}) {
        if (fail) throw ApiException(500, 'read');
        return good(path, start: start, length: length, serial: serial);
      },
    );
    expect(
      find.text(Errors.message(ApiException(500, ''), 'load the model')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.byKey(const ValueKey('model_viewer_retry')));
    await tester.pumpAndSettle();
    expect(find.text('1 triangle'), findsOneWidget);
  });

  testWidgets('back with nothing underneath goes to the folder', (
    tester,
  ) async {
    final router = await pumpViewer(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/files/prints');
    expect(find.text('folder:prints'), findsOneWidget);
  });
}
