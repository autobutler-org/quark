import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/document_properties_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The properties load behind a viewer's Properties sheet (#3275).
void main() {
  const saved = DocumentProperties(
    title: 'Report',
    author: 'Ada Lovelace',
    words: 10,
    pages: 3,
    countsSource: 'saved',
  );

  test('loads the saved properties', () async {
    final seen = <(String, String?)>[];
    final controller = DocumentPropertiesController(
      path: 'docs/report.docx',
      serial: 'usb1',
      loadProperties: (path, {serial}) async {
        seen.add((path, serial));
        return saved;
      },
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(seen, [('docs/report.docx', 'usb1')]);
    expect(controller.properties, saved);
    expect(controller.isLoading, isFalse);
    expect(controller.error, isNull);
  });

  test('a failed first load keeps the error and no properties', () async {
    final controller = DocumentPropertiesController(
      path: 'docs/missing.docx',
      loadProperties: (path, {serial}) async =>
          throw const ApiException(404, 'missing'),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.properties, isNull);
    expect(controller.error, isA<ApiException>());
    expect(controller.isLoading, isFalse);
  });

  test('a failed refresh keeps the properties already shown', () async {
    var calls = 0;
    final controller = DocumentPropertiesController(
      path: 'docs/report.docx',
      loadProperties: (path, {serial}) async {
        calls++;
        if (calls == 1) return saved;
        throw const ApiException(500, 'down');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.load();

    expect(controller.properties?.author, 'Ada Lovelace');
    expect(controller.error, isA<ApiException>());
    expect(controller.isLoading, isFalse);
  });

  test('a load that a newer one overtook is dropped', () async {
    final first = Completer<DocumentProperties>();
    var calls = 0;
    final controller = DocumentPropertiesController(
      path: 'docs/report.docx',
      loadProperties: (path, {serial}) {
        calls++;
        if (calls == 1) return first.future;
        return Future.value(const DocumentProperties(author: 'Second'));
      },
    );
    addTearDown(controller.dispose);

    final slow = controller.load();
    await controller.load();
    first.complete(const DocumentProperties(author: 'First'));
    await slow;

    expect(controller.properties?.author, 'Second');
    expect(controller.error, isNull);
  });
}
