import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/document_viewer_controller.dart';
import 'package:quark/pages/document_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/document_viewer/document_convert_conflict_dialog.dart';
import 'package:quark/widgets/document_viewer/document_converted_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// The read-only document viewer page (#3265): the document as the Quark
/// read it, where its links go, and "Open as Quark doc" with its conflict and
/// its warnings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final sample = QuarkDocument.parse(
    '{"type":"meta","version":1,"format":"docx","title":"CV"}\n'
    '{"type":"heading","level":1,"runs":[{"text":"Experience"}]}\n'
    '{"type":"paragraph","runs":[{"text":"See "},'
    '{"text":"my site","link":"https://example.com/me"},{"text":" or "},'
    '{"text":"a script","link":"javascript:alert(1)"}]}\n'
    '{"type":"table","rows":[{"cells":[{"colSpan":1,"rowSpan":1,"blocks":'
    '[{"type":"paragraph","runs":[{"text":"Lisbon"}]}]}]}]}\n'
    '{"type":"end","truncated":false,"words":8,"characters":40,'
    '"paragraphs":3,"warnings":[]}\n',
  );

  const clean = (
    path: 'papers/cv.qdoc',
    truncated: false,
    warnings: <String>[],
  );

  final opened = <Uri>[];
  final conversions = <bool>[];

  Future<GoRouter> pumpViewer(
    WidgetTester tester, {
    LoadDocumentFn? loadDocument,
    ConvertDocumentFn? convertDocument,
    Size size = const Size(1280, 800),
  }) async {
    setViewport(tester, size);
    opened.clear();
    conversions.clear();
    const filePath = 'papers/cv.docx';
    final controller = DocumentViewerController(
      path: filePath,
      loadDocument: loadDocument ?? (path, {serial}) async => sample,
      convertDocument:
          convertDocument ??
          (path, {serial, overwrite = false}) async {
            conversions.add(overwrite);
            return clean;
          },
    );
    addTearDown(controller.dispose);
    Widget stub(String name, GoRouterState state) =>
        Scaffold(body: Text('$name:${state.pathParameters['path']}'));
    final router = GoRouter(
      initialLocation: AppRoutes.documentViewerPath(filePath),
      routes: [
        for (final (name, prefix) in [
          ('folder', AppRoutes.files),
          ('editor', AppRoutes.docs),
        ])
          GoRoute(
            path: '$prefix/:path(.*)',
            builder: (_, state) => stub(name, state),
          ),
        GoRoute(
          path: '${AppRoutes.documentViewer}/:path(.*)',
          builder: (_, state) => DocumentViewerPage(
            filePath: state.pathParameters['path'] ?? '',
            controller: controller,
            openExternal: opened.add,
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

  String location(GoRouter router) =>
      router.routeInformationProvider.value.uri.toString();

  final openAsDoc = find.byKey(const ValueKey('document_viewer_open_as_doc'));

  for (final (label, size) in [
    ('a phone', const Size(360, 640)),
    ('a desktop', const Size(1280, 800)),
  ]) {
    testWidgets('shows the document under its file name on $label', (
      tester,
    ) async {
      await pumpViewer(tester, size: size);

      expect(find.text('cv.docx'), findsOneWidget);
      expect(find.byType(QuarkDocumentView), findsOneWidget);
      expect(find.text('Experience'), findsOneWidget);
      expect(find.text('Lisbon'), findsOneWidget);
      expect(openAsDoc, findsOneWidget);
      expect(
        find.byKey(const ValueKey('document_viewer_download')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a web link opens outside the app, and nothing else does', (
    tester,
  ) async {
    await pumpViewer(tester);

    await tester.tap(find.byKey(const ValueKey('document_link_0')));
    await tester.tap(find.byKey(const ValueKey('document_link_1')));
    await tester.pump();

    expect(opened, [Uri.parse('https://example.com/me')]);
  });

  testWidgets('a failed read says so, offers Retry and cannot convert', (
    tester,
  ) async {
    var fail = true;
    await pumpViewer(
      tester,
      loadDocument: (path, {serial}) async =>
          fail ? throw Exception('GET /previews/document: boom') : sample,
    );

    expect(find.text(Errors.couldNot('open the document')), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(tester.widget<QuarkBarChip>(openAsDoc).onPressed, isNull);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('document_view_retry')));
    await tester.pumpAndSettle();

    expect(find.text('Experience'), findsOneWidget);
    expect(tester.widget<QuarkBarChip>(openAsDoc).onPressed, isNotNull);
  });

  testWidgets('Open as Quark doc converts and opens the copy in the editor', (
    tester,
  ) async {
    final router = await pumpViewer(tester);

    await tester.tap(openAsDoc);
    await tester.pumpAndSettle();

    expect(conversions, [false]);
    expect(find.byType(DocumentConvertedDialog), findsNothing);
    expect(find.text('editor:papers/cv.qdoc'), findsOneWidget);
    // Back from the editor returns to the document.
    expect(
      Uri.parse(location(router)).queryParameters[AppRoutes.editorFromParam],
      '/document/papers/cv.docx',
    );
  });

  testWidgets('what the copy left out is said before it opens', (tester) async {
    final router = await pumpViewer(
      tester,
      convertDocument: (path, {serial, overwrite = false}) async => (
        path: 'papers/cv.qdoc',
        truncated: true,
        warnings: const ['Images are left out.'],
      ),
    );

    await tester.tap(openAsDoc);
    await tester.pumpAndSettle();

    expect(find.text('Saved as "cv.qdoc"'), findsOneWidget);
    expect(find.text('• Images are left out.'), findsOneWidget);
    expect(find.textContaining('too long to convert'), findsOneWidget);
    expect(location(router), '/document/papers/cv.docx');

    await tester.tap(find.byKey(const ValueKey('document_converted_open')));
    await tester.pumpAndSettle();

    expect(find.text('editor:papers/cv.qdoc'), findsOneWidget);
  });

  testWidgets('"Not now" keeps the reader on the document', (tester) async {
    final router = await pumpViewer(
      tester,
      convertDocument: (path, {serial, overwrite = false}) async => (
        path: 'papers/cv.qdoc',
        truncated: false,
        warnings: const ['Images are left out.'],
      ),
    );

    await tester.tap(openAsDoc);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document_converted_later')));
    await tester.pumpAndSettle();

    expect(location(router), '/document/papers/cv.docx');
    expect(find.text('Experience'), findsOneWidget);
  });

  group('when the .qdoc is already there', () {
    Future<DocumentConversion> conflicting(
      String path, {
      String? serial,
      bool overwrite = false,
    }) async {
      conversions.add(overwrite);
      if (!overwrite) throw const ApiException(409, 'exists');
      return clean;
    }

    testWidgets('the reader is asked, and can open the one that is there', (
      tester,
    ) async {
      await pumpViewer(tester, convertDocument: conflicting);

      await tester.tap(openAsDoc);
      await tester.pumpAndSettle();

      expect(find.byType(DocumentConvertConflictDialog), findsOneWidget);
      expect(find.textContaining('"cv.qdoc" is already here'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('document_convert_open_existing')),
      );
      await tester.pumpAndSettle();

      expect(conversions, [false]);
      expect(find.text('editor:papers/cv.qdoc'), findsOneWidget);
    });

    testWidgets('Replace converts again over it', (tester) async {
      await pumpViewer(tester, convertDocument: conflicting);

      await tester.tap(openAsDoc);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_convert_replace')));
      await tester.pumpAndSettle();

      expect(conversions, [false, true]);
      expect(find.text('editor:papers/cv.qdoc'), findsOneWidget);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final router = await pumpViewer(tester, convertDocument: conflicting);

      await tester.tap(openAsDoc);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_convert_cancel')));
      await tester.pumpAndSettle();

      expect(conversions, [false]);
      expect(location(router), '/document/papers/cv.docx');
    });
  });

  testWidgets('a failed conversion says so and stays on the document', (
    tester,
  ) async {
    final router = await pumpViewer(
      tester,
      convertDocument: (path, {serial, overwrite = false}) async =>
          throw Exception('POST /files/convert/document: boom'),
    );

    await tester.tap(openAsDoc);
    await tester.pumpAndSettle();

    expect(find.text(Errors.couldNot('convert the document')), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(location(router), '/document/papers/cv.docx');
  });
}
