import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/document_viewer_controller.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The document viewer's state (#3265): the document the Quark read, a
/// failed read, and the conversion behind "Open as Quark doc".
void main() {
  final sample = QuarkDocument.parse(
    '{"type":"meta","version":1,"format":"docx"}\n'
    '{"type":"paragraph","runs":[{"text":"Hello"}]}\n'
    '{"type":"end","truncated":false,"words":1,"characters":5,'
    '"paragraphs":1,"warnings":[]}\n',
  );

  LoadDocumentFn loaderOf(QuarkDocument document, {List<String>? asked}) =>
      (path, {serial}) async {
        asked?.add('$path@$serial');
        return document;
      };

  Future<DocumentConversion> neverConverts(
    String path, {
    String? serial,
    bool overwrite = false,
  }) => fail('nothing should convert');

  test('load asks for the file on its drive and holds the blocks', () async {
    final asked = <String>[];
    final controller = DocumentViewerController(
      path: 'papers/cv.docx',
      serial: 'usb1',
      loadDocument: loaderOf(sample, asked: asked),
      convertDocument: neverConverts,
    );
    addTearDown(controller.dispose);
    expect(controller.isLoading, isTrue);
    expect(controller.canConvert, isFalse);

    await controller.load();

    expect(asked, ['papers/cv.docx@usb1']);
    expect(controller.isLoading, isFalse);
    expect(controller.error, isNull);
    expect(controller.document.blocks, hasLength(1));
    expect(controller.canConvert, isTrue);
  });

  test('a failed read is kept as the error, and a retry clears it', () async {
    var fail = true;
    final controller = DocumentViewerController(
      path: 'cv.docx',
      loadDocument: (path, {serial}) async =>
          fail ? throw const ApiException(400, 'not a document') : sample,
      convertDocument: neverConverts,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.error, isA<ApiException>());
    expect(controller.document.isEmpty, isTrue);
    expect(controller.canConvert, isFalse);

    fail = false;
    await controller.load();

    expect(controller.error, isNull);
    expect(controller.document.isEmpty, isFalse);
  });

  test('a slow first read does not overwrite the reload after it', () async {
    final first = Completer<QuarkDocument>();
    var calls = 0;
    final controller = DocumentViewerController(
      path: 'cv.docx',
      loadDocument: (path, {serial}) =>
          calls++ == 0 ? first.future : Future.value(sample),
      convertDocument: neverConverts,
    );
    addTearDown(controller.dispose);

    final slow = controller.load();
    await controller.load();
    first.complete(const QuarkDocument.empty());
    await slow;

    expect(controller.document.blocks, hasLength(1));
    expect(controller.isLoading, isFalse);
  });

  test('convert passes overwrite along and returns what was written', () async {
    final asked = <String>[];
    final pending = Completer<DocumentConversion>();
    final controller = DocumentViewerController(
      path: 'papers/cv.docx',
      serial: 'usb1',
      loadDocument: loaderOf(sample),
      convertDocument: (path, {serial, overwrite = false}) {
        asked.add('$path@$serial overwrite=$overwrite');
        return pending.future;
      },
    );
    addTearDown(controller.dispose);
    await controller.load();

    final converting = controller.convert(overwrite: true);
    expect(controller.isConverting, isTrue);
    expect(controller.canConvert, isFalse);
    pending.complete((
      path: 'papers/cv.qdoc',
      truncated: false,
      warnings: const ['Images are left out.'],
    ));
    final result = await converting;

    expect(asked, ['papers/cv.docx@usb1 overwrite=true']);
    expect(result.path, 'papers/cv.qdoc');
    expect(result.warnings, ['Images are left out.']);
    expect(controller.isConverting, isFalse);
    expect(controller.canConvert, isTrue);
  });

  test('a conflict reaches the caller and leaves the viewer usable', () async {
    final controller = DocumentViewerController(
      path: 'cv.docx',
      loadDocument: loaderOf(sample),
      convertDocument: (path, {serial, overwrite = false}) async =>
          throw const ApiException(409, 'exists'),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await expectLater(
      controller.convert(),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );

    expect(controller.isConverting, isFalse);
    expect(controller.error, isNull);
    expect(controller.document.blocks, hasLength(1));
  });
}
