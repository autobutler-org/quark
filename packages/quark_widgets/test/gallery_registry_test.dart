import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_gallery_docs.dart' as gen;

/// A public class whose superclass name ends in `Widget` — which is what makes
/// it something the gallery can render.
final RegExp _widgetClass = RegExp(
  r'^(?:(?:abstract|base|final|interface|sealed)\s+)*'
  r'class\s+([A-Z]\w*)(?:<[^>]*>)?\s+extends\s+\w*Widget\b',
  multiLine: true,
);

/// The files the barrel re-exports, as paths under lib/.
List<File> _exportedFiles() {
  final barrel = File('lib/quark_widgets.dart').readAsStringSync();
  return RegExp(
    r"^export\s+'([^']+)';",
    multiLine: true,
  ).allMatches(barrel).map((m) => File('lib/${m.group(1)}')).toList();
}

void main() {
  test('every exported widget has a gallery entry', () {
    final registry = File(
      'examples/widget_gallery/lib/registry.dart',
    ).readAsStringSync();

    final exported = _exportedFiles();
    expect(
      exported,
      isNotEmpty,
      reason: 'lib/quark_widgets.dart exports nothing',
    );

    for (final file in exported) {
      expect(
        file.existsSync(),
        isTrue,
        reason: '${file.path} is exported from the barrel but does not exist',
      );

      for (final match in _widgetClass.allMatches(file.readAsStringSync())) {
        final name = match.group(1)!;
        // The entry's own name, so a widget mentioned only in a comment or in
        // another widget's entry does not count.
        expect(
          registry.contains("name: '$name'"),
          isTrue,
          reason:
              '$name is exported from quark_widgets but has no entry in '
              'examples/widget_gallery/lib/registry.dart. Every widget ships '
              'with a gallery entry — see the widget package rules in '
              'AGENTS.md.',
        );
      }
    }
  });

  test('docs.g.dart is up to date', () {
    final generated = gen.renderDocsSource(
      gen.collectDocs(Directory('lib/src')),
    );
    final committed = File(
      'examples/widget_gallery/lib/docs.g.dart',
    ).readAsStringSync();

    expect(
      committed,
      generated,
      reason:
          'The generated widget docs are stale. Run '
          '`make -C packages/quark_widgets generate/docs`.',
    );
  });
}
