import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_file_picker_platform.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

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

  testWidgets('asks the right device for the file', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PdfViewerPage(
          filePath: 'papers/report.pdf',
          name: 'report.pdf',
          serial: 'disk-2',
        ),
      ),
    );

    final ref =
        tester.widget<PdfViewer>(find.byType(PdfViewer)).documentRef
            as PdfDocumentRefUri;
    expect(ref.uri.queryParameters, {
      'filePath': 'papers/report.pdf',
      'serial': 'disk-2',
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the loader while the PDF loads', (tester) async {
    await pumpViewer(tester);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final context = tester.element(find.byType(PdfViewer));

    final banner = viewer.params.loadingBannerBuilder!(context, 0, null);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: banner)));

    expect(find.byType(QuarkLoader), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the back button calls onClose', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerPage(
          filePath: 'papers/report.pdf',
          name: 'report.pdf',
          onClose: () => closed++,
        ),
      ),
    );

    await tester.tap(find.byType(BackButton));
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('a long name fits the top bar on a $label screen', (
      tester,
    ) async {
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfViewerPage(
            filePath: 'papers/report.pdf',
            name: '${'quarterly report ' * 6}.pdf',
            onClose: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('pdf_viewer_download')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pdf_viewer_open_with')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  group('when the PDF is gone from the Quark', () {
    late Directory saveDir;
    setUp(() {
      // A desktop download asks where to save before it downloads (#3150).
      saveDir = Directory.systemTemp.createTempSync('pdf_viewer_save');
      FilePickerPlatform.instance = FakeFilePickerPlatform(saveDir);
      sharedHttpClientFactory = () =>
          MockClient((_) async => http.Response('', 404));
      resetSharedHttpClient();
    });
    tearDown(() {
      sharedHttpClientFactory = buildLocalTrustHttpClient;
      resetSharedHttpClient();
      saveDir.deleteSync(recursive: true);
    });

    for (final (key, sentence) in [
      ('pdf_viewer_download', "Couldn't download the file — it's no"),
      ('pdf_viewer_open_with', "Couldn't open the file — it's no"),
    ]) {
      testWidgets('$key says so in plain words', (tester) async {
        await pumpViewer(tester);

        await tester.tap(find.byKey(ValueKey(key)));
        // The fake client and save dialog answer in microtasks; no real I/O
        // to wait on.
        await tester.pump();
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining(sentence), findsOneWidget);
        expect(find.textContaining('404'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
