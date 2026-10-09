import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

// These run off web, where the page uses pdfrx. The browser's own viewer is
// an iframe in a platform view, which `flutter test` cannot build.
void main() {
  Future<void> pumpViewer(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: PdfViewerPage(filePath: 'papers/report.pdf', name: 'report.pdf'),
    ),
  );

  testWidgets('offers Download and Open with in the top bar', (tester) async {
    await pumpViewer(tester);

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf_viewer_download')), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    // Tests are not web, so the system hand-off is offered too.
    expect(find.byKey(const ValueKey('pdf_viewer_open_with')), findsOneWidget);
    expect(find.byTooltip('Open with…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reads the file by URL, in ranges, without a token in it', (
    tester,
  ) async {
    await pumpViewer(tester);

    final ref =
        tester.widget<PdfViewer>(find.byType(PdfViewer)).documentRef
            as PdfDocumentRefUri;
    expect(ref.uri.path, '/api/v0/files/download');
    expect(ref.uri.queryParameters, {'filePath': 'papers/report.pdf'});
    expect(ref.preferRangeAccess, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('has pdfrx\'s scroll thumb and full-speed wheel scrolling', (
    tester,
  ) async {
    await pumpViewer(tester);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final context = tester.element(find.byType(PdfViewer));

    final overlays = viewer.params.viewerOverlayBuilder!(
      context,
      const Size(360, 640),
      (_) => false,
    );
    final thumb = overlays.single as PdfViewerScrollThumb;
    expect(thumb.controller, same(viewer.controller));
    expect(thumb.orientation, ScrollbarOrientation.right);
    expect(viewer.params.scrollByMouseWheel, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a PDF that cannot be loaded says so in plain words', (
    tester,
  ) async {
    await pumpViewer(tester);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final context = tester.element(find.byType(PdfViewer));

    // pdfrx calls this with whatever the load threw.
    final banner = viewer.params.errorBannerBuilder!(
      context,
      Exception('SocketException: errno = 61, http://quark.local/secret'),
      null,
      viewer.documentRef,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: banner)));

    expect(find.byType(EmptyStateWidget), findsOneWidget);
    expect(find.textContaining("Couldn't open the file"), findsOneWidget);
    expect(find.textContaining('errno'), findsNothing);
  });
}
