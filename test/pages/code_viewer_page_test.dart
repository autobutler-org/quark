import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/pages/code_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// The code viewer page (#2991): what it shows for a file, a file too large
/// for one page, and a failed read, and where its bar's buttons go.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ReadCodeRangeFn readerOver(String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return (path, {required start, required length, serial}) async => (
      bytes: Uint8List.sublistView(
        bytes,
        start.clamp(0, bytes.length),
        (start + length).clamp(0, bytes.length),
      ),
      totalSize: bytes.length,
    );
  }

  Future<GoRouter> pumpViewer(
    WidgetTester tester, {
    required ReadCodeRangeFn readRange,
    String filePath = 'src/app/main.go',
    int pageBytes = 4096,
  }) async {
    final controller = CodeViewerController(
      path: filePath,
      readRange: readRange,
      pageBytes: pageBytes,
    );
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.codeViewerPath(filePath),
      routes: [
        GoRoute(
          path: '${AppRoutes.files}/:path(.*)',
          builder: (_, state) =>
              Scaffold(body: Text('folder:${state.pathParameters['path']}')),
        ),
        GoRoute(
          path: '${AppRoutes.plaintextEditor}/:path(.*)',
          builder: (_, state) =>
              Scaffold(body: Text('editor:${state.pathParameters['path']}')),
        ),
        GoRoute(
          path: '${AppRoutes.codeViewer}/:path(.*)',
          builder: (_, state) => CodeViewerPage(
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

  bool editEnabled(WidgetTester tester) =>
      tester
          .widget<QuarkBarChip>(find.byKey(const ValueKey('code_viewer_edit')))
          .onPressed !=
      null;

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('shows the file under its name at ${size.width}', (
      tester,
    ) async {
      setViewport(tester, size);

      await pumpViewer(
        tester,
        readRange: readerOver('package main\n\nfunc main() {}\n'),
      );

      expect(find.text('main.go'), findsOneWidget);
      final viewer = tester.widget<QuarkCodeViewer>(
        find.byType(QuarkCodeViewer),
      );
      expect(viewer.lines, ['package main', '', 'func main() {}']);
      expect(viewer.language, CodeLanguage.go);
      expect(viewer.hasMore, isFalse);
      expect(viewer.statusLabel, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Edit hands a fully read file to the plaintext editor', (
    tester,
  ) async {
    final router = await pumpViewer(tester, readRange: readerOver('a: 1\n'));
    expect(editEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('code_viewer_edit')));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      // It carries where it was opened from, so the editor's Back returns
      // to the viewer rather than to the folder (#3186).
      '/edit/src/app/main.go?from=/code/src/app/main.go',
    );
  });

  testWidgets('a file larger than a page says how much is shown, and is not '
      'offered to the editor', (tester) async {
    final content = List.generate(4000, (i) => 'line $i').join('\n');
    await pumpViewer(tester, readRange: readerOver(content), pageBytes: 2048);

    final viewer = tester.widget<QuarkCodeViewer>(find.byType(QuarkCodeViewer));
    expect(viewer.hasMore, isTrue);
    expect(viewer.statusLabel, startsWith('Showing 2.0 KB of '));
    expect(editEnabled(tester), isFalse);
  });

  testWidgets('a failed read shows a sentence, never the exception', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      readRange: (path, {required start, required length, serial}) =>
          throw const ApiException(500, 'GET /api/v0/files/download boom'),
    );

    final viewer = tester.widget<QuarkCodeViewer>(find.byType(QuarkCodeViewer));
    expect(
      viewer.error,
      Errors.message(const ApiException(500, ''), 'load the file'),
    );
    expect(find.textContaining('boom'), findsNothing);
    expect(editEnabled(tester), isFalse);
  });

  testWidgets('back with nothing underneath lands in the containing folder', (
    tester,
  ) async {
    final router = await pumpViewer(tester, readRange: readerOver('x\n'));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/files/src/app',
    );
    expect(find.text('folder:src/app'), findsOneWidget);
  });
}
