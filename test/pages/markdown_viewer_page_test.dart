import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/controllers/markdown_viewer_controller.dart';
import 'package:quark/pages/markdown_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/markdown_viewer/markdown_viewer_image.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// The Markdown viewer page (#2987): the rendered file, its source toggle,
/// where links go, and that nothing off the Quark loads unasked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sample =
      '# Trip notes\n\n'
      '- [x] book flights\n'
      '- [ ] pack\n\n'
      '| City | Nights |\n| --- | ---: |\n| Lisbon | 3 |\n\n'
      '```dart\nvoid main() {}\n```\n\n'
      '<script>alert("pwned")</script>\n\n'
      '[next](../other/plan.md) and [site](https://example.com/page)\n\n'
      '![remote cat](https://example.com/cat.png)\n';

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

  final opened = <Uri>[];

  /// Runs [body] with every `http.Client` answering [svg] and recording
  /// each request in [requests]: `flutter_svg` fetches through package:http,
  /// which the test binding's 400-for-everything does not cover usefully.
  Future<void> withSvgServer(
    String svg,
    List<http.Request> requests,
    Future<void> Function() body,
  ) => http.runWithClient(
    body,
    () => MockClient((request) async {
      requests.add(request);
      return http.Response(svg, 200);
    }),
  );

  /// Waits on the real-time fetch an `SvgPicture` started, then lets it paint.
  Future<void> settleSvg(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<GoRouter> pumpViewer(
    WidgetTester tester, {
    String content = sample,
    ReadCodeRangeFn? readRange,
    String filePath = 'notes/trip/readme.md',
    int maxBytes = 64 * 1024,
  }) async {
    opened.clear();
    final read = readRange ?? readerOver(content);
    final controller = MarkdownViewerController(
      path: filePath,
      readRange: read,
      maxBytes: maxBytes,
    );
    final source = CodeViewerController(path: filePath, readRange: read);
    addTearDown(controller.dispose);
    addTearDown(source.dispose);
    Widget stub(String name, GoRouterState state) =>
        Scaffold(body: Text('$name:${state.pathParameters['path']}'));
    final router = GoRouter(
      initialLocation: AppRoutes.markdownViewerPath(filePath),
      routes: [
        for (final (name, prefix) in [
          ('folder', AppRoutes.files),
          ('editor', AppRoutes.plaintextEditor),
          ('view', AppRoutes.viewFile),
        ])
          GoRoute(
            path: '$prefix/:path(.*)',
            builder: (_, state) => stub(name, state),
          ),
        GoRoute(
          path: '${AppRoutes.markdownViewer}/:path(.*)',
          builder: (_, state) => MarkdownViewerPage(
            filePath: state.pathParameters['path'] ?? '',
            controller: controller,
            sourceController: source,
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

  QuarkMarkdownView view(WidgetTester tester) =>
      tester.widget<QuarkMarkdownView>(find.byType(QuarkMarkdownView));

  bool editEnabled(WidgetTester tester) =>
      tester
          .widget<QuarkBarChip>(
            find.byKey(const ValueKey('markdown_viewer_edit')),
          )
          .onPressed !=
      null;

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('renders the file under its name at ${size.width}', (
      tester,
    ) async {
      setViewport(tester, size);

      await pumpViewer(tester);

      expect(find.text('readme.md'), findsOneWidget);
      expect(find.textContaining('Trip notes'), findsOneWidget);
      expect(find.textContaining('# Trip notes'), findsNothing);
      expect(view(tester).statusLabel, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('raw HTML shows as text', (tester) async {
    await pumpViewer(tester);
    await tester.scrollUntilVisible(
      find.textContaining('<script>alert("pwned")</script>'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('<script>alert("pwned")</script>'),
      findsOneWidget,
    );
  });

  testWidgets('the toggle swaps the rendered view for the source and back', (
    tester,
  ) async {
    await pumpViewer(tester);
    expect(find.byType(QuarkCodeViewer), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('markdown_viewer_source_toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuarkMarkdownView), findsNothing);
    final source = tester.widget<QuarkCodeViewer>(find.byType(QuarkCodeViewer));
    expect(source.lines.first, '# Trip notes');
    expect(find.text('Rendered'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('markdown_viewer_source_toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuarkMarkdownView), findsOneWidget);
    expect(find.byType(QuarkCodeViewer), findsNothing);
  });

  testWidgets('a relative link opens the file it points at', (tester) async {
    final router = await pumpViewer(tester);

    view(tester).onLinkTap!('../other/plan.md');
    await tester.pumpAndSettle();

    expect(location(router), '/view/notes/other/plan.md');
    expect(opened, isEmpty);
  });

  testWidgets('a web link opens outside the app; script links go nowhere', (
    tester,
  ) async {
    final router = await pumpViewer(tester);

    view(tester).onLinkTap!('https://example.com/page');
    view(tester).onLinkTap!('javascript:alert(1)');
    view(tester).onLinkTap!('#heading');
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://example.com/page')]);
    expect(location(router), '/markdown/notes/trip/readme.md');
  });

  testWidgets('a remote image is not fetched until the reader asks', (
    tester,
  ) async {
    await pumpViewer(tester, content: '![cat](https://example.com/cat.png)\n');

    final load = find.byKey(
      const ValueKey('markdown_viewer_load_image_https://example.com/cat.png'),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('Load remote image: cat'), findsOneWidget);
    expect(
      tester.widget<MarkdownViewerImage>(find.byType(MarkdownViewerImage)),
      isA<MarkdownViewerImage>().having(
        (image) => image.remoteAllowed,
        'remoteAllowed',
        isFalse,
      ),
    );

    await tester.tap(load);
    await tester.pump();

    expect(load, findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://example.com/cat.png');
    // The test binding answers every request with 400; the alt text stands in.
    await tester.pumpAndSettle();
    tester.takeException();
  });

  testWidgets('a relative image loads from the file\'s folder on the Quark', (
    tester,
  ) async {
    await pumpViewer(tester, content: '![map](img/map.png)\n');

    final image = tester.widget<Image>(find.byType(Image));
    final url = Uri.parse((image.image as NetworkImage).url);
    expect(url.path, '/api/v0/files/download');
    expect(url.queryParameters.values, contains('notes/trip/img/map.png'));
    await tester.pumpAndSettle();
    tester.takeException();
  });

  testWidgets('an SVG on the Quark renders as a vector, with auth', (
    tester,
  ) async {
    final requests = <http.Request>[];
    // No size and no viewBox: the viewer has to give it one to lay out.
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="9" '
        'height="9"/></svg>';
    await withSvgServer(svg, requests, () async {
      await pumpViewer(tester, content: '![logo](img/Logo.SVG)\n');
      await settleSvg(tester);
    });

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('logo'), findsNothing);
    final url = requests.single.url;
    expect(url.path, '/api/v0/files/download');
    expect(url.queryParameters.values, contains('notes/trip/img/Logo.SVG'));
    final loader =
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
            as SvgNetworkLoader;
    expect(loader.headers, FilesService.instance.authHeaders);
  });

  testWidgets('a remote SVG waits for the reader, then renders as a vector', (
    tester,
  ) async {
    const src = 'https://example.com/badge.svg?style=flat';
    final requests = <http.Request>[];
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="80" '
        'height="20"><rect width="80" height="20"/></svg>';
    await withSvgServer(svg, requests, () async {
      await pumpViewer(tester, content: '![build]($src)\n');
      await settleSvg(tester);
      expect(find.byType(SvgPicture), findsNothing);
      expect(requests, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('markdown_viewer_load_image_$src')),
      );
      await settleSvg(tester);
    });

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(requests.single.url.toString(), src);
    final loader =
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
            as SvgNetworkLoader;
    expect(loader.headers, isNull);
  });

  testWidgets('Edit hands the file to the plaintext editor', (tester) async {
    final router = await pumpViewer(tester);
    expect(editEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('markdown_viewer_edit')));
    await tester.pumpAndSettle();

    expect(
      location(router),
      '/edit/notes/trip/readme.md?from=/markdown/notes/trip/readme.md',
    );
  });

  testWidgets('a file past the cap says how much is rendered, and is not '
      'offered to the editor', (tester) async {
    await pumpViewer(tester, content: 'word word\n\n' * 500, maxBytes: 2048);

    expect(
      view(tester).statusLabel,
      startsWith('Showing the first 2.0 KB of '),
    );
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

    expect(
      view(tester).error,
      Errors.message(const ApiException(500, ''), 'load the file'),
    );
    expect(find.textContaining('boom'), findsNothing);
    expect(editEnabled(tester), isFalse);
  });

  testWidgets('back with nothing underneath lands in the containing folder', (
    tester,
  ) async {
    final router = await pumpViewer(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(location(router), '/files/notes/trip');
  });
}
