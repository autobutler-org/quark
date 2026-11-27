import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark/utils/document_viewer_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The document viewer's two requests (#3265): the block stream it draws,
/// and the conversion behind "Open as Quark doc".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.BaseRequest>[];

  void respondWith(
    http.StreamedResponse Function(http.BaseRequest request) respond,
  ) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient.streaming((request, _) async {
      requests.add(request);
      return respond(request);
    });
  }

  http.StreamedResponse text(String body, int status) =>
      http.StreamedResponse(Stream.value(utf8.encode(body)), status);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  const stream =
      '{"type":"meta","version":1,"format":"docx","title":"Café menu"}\n'
      '{"type":"heading","level":1,"runs":[{"text":"Experience"}]}\n'
      '{"type":"paragraph","align":"center","runs":[{"text":"Wrote ",'
      '"bold":true},{"text":"things","link":"https://example.com/"}]}\n'
      '{"type":"end","truncated":false,"words":3,"characters":18,'
      '"paragraphs":2,"warnings":["Headers and footers are left out."]}\n';

  group('document', () {
    test('asks the preview endpoint and parses the block stream', () async {
      // Split between the two bytes of the é, as a network read may.
      final bytes = utf8.encode(stream);
      final cut = bytes.indexOf(0xC3) + 1;
      respondWith(
        (_) => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut)]),
          200,
        ),
      );

      final document = await PreviewsService.document(
        'papers/my cv.docx',
        serial: 'usb1',
      );

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v0/previews/document');
      expect(request.url.queryParameters['filePath'], 'papers/my cv.docx');
      expect(request.url.queryParameters['serial'], 'usb1');
      expect(document.metadata?.title, 'Café menu');
      expect(document.blocks, hasLength(2));
      expect(document.blocks.first, isA<QuarkDocumentHeading>());
      final paragraph = document.blocks.last as QuarkDocumentParagraph;
      expect(paragraph.runs.last.link, 'https://example.com/');
      expect(document.summary?.words, 3);
      expect(document.summary?.warnings, ['Headers and footers are left out.']);
    });

    test('leaves the serial out for the internal drive', () async {
      respondWith((_) => text(stream, 200));

      await PreviewsService.document('cv.odt');

      expect(
        requests.single.url.queryParameters.containsKey('serial'),
        isFalse,
      );
    });

    test('a stream the Quark cut off is an error, not half a document', () {
      final cut = stream.substring(0, stream.indexOf('{"type":"end"'));
      respondWith((_) => text(cut, 200));

      expect(PreviewsService.document('cv.docx'), throwsFormatException);
    });

    test('a refusal carries its status', () async {
      respondWith((_) => text('{"error":"not a document"}', 400));

      await expectLater(
        PreviewsService.document('cv.docx'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('a stream past the cap is refused, not held', () async {
      final megabyte = List<int>.filled(1024 * 1024, 0x20);
      respondWith(
        (_) => http.StreamedResponse(
          Stream.fromIterable(
            List.filled(
              DocumentViewerConfig.maxPreviewBytes ~/ megabyte.length + 1,
              megabyte,
            ),
          ),
          200,
        ),
      );

      await expectLater(
        PreviewsService.document('huge.docx'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('previewPartUrl', () {
    test('names the part, the document and its drive', () {
      final url = previewPartUrl(
        'word/media/image 1.png',
        filePath: 'papers/my cv.docx',
        serial: 'usb1',
      );

      expect(url.path, '/api/v0/previews/part');
      expect(url.queryParameters['part'], 'word/media/image 1.png');
      expect(url.queryParameters['filePath'], 'papers/my cv.docx');
      expect(url.queryParameters['serial'], 'usb1');
    });
  });

  group('convertDocumentToQdoc', () {
    test('posts the document and reads where the copy landed', () async {
      respondWith(
        (_) => text(
          '{"path":"papers/cv.qdoc","truncated":true,"words":120,'
          '"warnings":["Images are left out."]}',
          200,
        ),
      );

      final result = await FilesService.convertDocumentToQdoc(
        'papers/cv.docx',
        serial: 'usb1',
        overwrite: true,
      );

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/files/convert/document');
      expect(request.url.queryParameters, {
        'filePath': 'papers/cv.docx',
        'serial': 'usb1',
        'overwrite': 'true',
      });
      expect(result.path, 'papers/cv.qdoc');
      expect(result.truncated, isTrue);
      expect(result.warnings, ['Images are left out.']);
    });

    test('does not ask to overwrite unless told to', () async {
      respondWith((_) => text('{"path":"cv.qdoc","warnings":[]}', 200));

      final result = await FilesService.convertDocumentToQdoc('cv.docx');

      expect(requests.single.url.queryParameters, {'filePath': 'cv.docx'});
      expect(result.truncated, isFalse);
      expect(result.warnings, isEmpty);
    });

    test('an existing .qdoc is a 409 for the caller to ask about', () async {
      respondWith((_) => text('{"error":"exists"}', 409));

      await expectLater(
        FilesService.convertDocumentToQdoc('cv.docx'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
        ),
      );
    });

    test('an answer with no path is an error', () async {
      respondWith((_) => text('{"warnings":[]}', 200));

      await expectLater(
        FilesService.convertDocumentToQdoc('cv.docx'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
