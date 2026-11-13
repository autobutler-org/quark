import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Icons;
import 'package:quark_icons/quark_icons.dart';

/// #4100: one weight per action, and no raw `Icons.` outside the catalog.
void main() {
  test('each duplicated stem points at the weight the catalog names', () {
    expect(QuarkIcons.add, Icons.add_rounded);
    expect(QuarkIcons.close, Icons.close_rounded);
    expect(QuarkIcons.search, Icons.search_rounded);
    expect(QuarkIcons.arrow_back, Icons.arrow_back_rounded);
    expect(QuarkIcons.chevron_left, Icons.chevron_left_rounded);
    expect(QuarkIcons.chevron_right, Icons.chevron_right_rounded);
    expect(QuarkIcons.expand_less, Icons.expand_less_rounded);
    expect(QuarkIcons.expand_more, Icons.expand_more_rounded);
    expect(QuarkIcons.home, Icons.home_rounded);
    expect(QuarkIcons.check, Icons.check_rounded);
    expect(QuarkIcons.check_circle_outline, Icons.check_circle_outline);
    expect(QuarkIcons.circle_outlined, Icons.circle_outlined);
    expect(QuarkIcons.folder, Icons.folder_outlined);
    expect(QuarkIcons.folder_open, Icons.folder_open_outlined);
    expect(QuarkIcons.star, Icons.star_rounded);
    expect(QuarkIcons.star_border, Icons.star_outline_rounded);
    expect(QuarkIcons.storage, Icons.storage_rounded);
    expect(QuarkIcons.save, Icons.save_outlined);
    expect(QuarkIcons.visibility, Icons.visibility_outlined);
    expect(QuarkIcons.visibility_off, Icons.visibility_off_outlined);
    expect(QuarkIcons.play_arrow, Icons.play_arrow);
    expect(QuarkIcons.grid_view, Icons.grid_view_rounded);
    expect(QuarkIcons.light_mode, Icons.light_mode_rounded);
    expect(QuarkIcons.dark_mode, Icons.dark_mode_rounded);
    expect(QuarkIcons.key, Icons.key_outlined);
    expect(QuarkIcons.link, Icons.link_outlined);
    expect(QuarkIcons.tune, Icons.tune_rounded);
    expect(QuarkIcons.broken_image, Icons.broken_image_outlined);
    expect(QuarkIcons.photo_library, Icons.photo_library_outlined);
    expect(QuarkIcons.warning_amber, Icons.warning_amber);
    expect(QuarkIcons.content_copy, Icons.content_copy);

    expect(QuarkIcons.freeze_panes, Icons.horizontal_split);
    expect(QuarkIcons.format_number, Icons.numbers);
    expect(QuarkIcons.font_family, Icons.type_specimen);
    expect(QuarkIcons.group_elements, Icons.group_work);
    expect(QuarkIcons.ungroup_elements, Icons.group_off);
    expect(QuarkIcons.chart_gridlines, Icons.border_horizontal);
    expect(QuarkIcons.wireframe, Icons.grid_4x4);
    expect(QuarkIcons.cpu, Icons.developer_board);
    expect(QuarkIcons.memory, Icons.memory);

    expect(QuarkIcons.table_chart, Icons.table_chart);
    expect(QuarkIcons.table_chart_outlined, Icons.table_chart_outlined);
    expect(QuarkIcons.slideshow, Icons.slideshow);
    expect(QuarkIcons.slideshow_outlined, Icons.slideshow_outlined);
    expect(QuarkIcons.edit_document, Icons.edit_document);
  });

  test('the retired weight aliases are gone', () {
    const retired = [
      'add_rounded',
      'arrow_back_rounded',
      'broken_image_outlined',
      'check_rounded',
      'check_circle_outline_rounded',
      'check_circle_rounded',
      'chevron_left_rounded',
      'chevron_right_rounded',
      'close_rounded',
      'clear_rounded',
      'dark_mode_outlined',
      'dark_mode_rounded',
      'expand_more_rounded',
      'folder_outlined',
      'folder_rounded',
      'folder_open_outlined',
      'folder_open_rounded',
      'grid_view_outlined',
      'grid_view_rounded',
      'home_filled',
      'home_rounded',
      'key_outlined',
      'key_rounded',
      'light_mode_outlined',
      'light_mode_rounded',
      'link_outlined',
      'link_rounded',
      'photo_library_outlined',
      'play_arrow_rounded',
      'save_outlined',
      'search_rounded',
      'star_rounded',
      'star_outline_rounded',
      'storage_outlined',
      'storage_rounded',
      'tune_outlined',
      'tune_rounded',
      'visibility_outlined',
      'visibility_off_outlined',
      'copy_outlined',
    ];
    final offenders = <String>[];
    for (final path in _dartFiles(_scanRoots)) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final name in retired) {
          if (lines[i].contains('QuarkIcons.$name') ||
              lines[i].contains('IconData $name')) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('production code draws QuarkIcons, not Icons', () {
    final icon = RegExp(r'(?<![A-Za-z0-9_])Icons\.');
    final offenders = <String>[];
    for (final path in _dartFiles(_scanRoots)) {
      final source = _stripComments(File(path).readAsStringSync());
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (icon.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Add a QuarkIcons alias and call that. Doc comments may still name Icons.',
    );
  });

  test('health CPU and memory use the icon for that reading', () {
    final source = File(
      'lib/widgets/health/health_body.dart',
    ).readAsStringSync();
    expect(
      RegExp(r"label: 'CPU',\s*icon: QuarkIcons\.cpu").hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(r"label: 'Memory',\s*icon: QuarkIcons\.memory").hasMatch(source),
      isTrue,
    );
    expect(source.contains('disc_full'), isTrue);
  });
}

const _scanRoots = [
  'lib',
  'packages/quark_widgets/lib',
  'packages/data_table/lib',
  'packages/quark_slides/lib',
];

Iterable<String> _dartFiles(List<String> roots) sync* {
  for (final root in roots) {
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity.path;
    }
  }
}

/// Source with `//` and `/* */` comments removed, so an example in a doc can
/// still mention `Icons.`.
String _stripComments(String source) {
  final out = StringBuffer();
  var block = false;
  for (final line in source.split('\n')) {
    if (block) {
      final end = line.indexOf('*/');
      if (end < 0) {
        out.writeln();
        continue;
      }
      block = false;
      out.writeln(_withoutLineComment(line.substring(end + 2)));
      continue;
    }
    final start = _blockStart(line);
    if (start >= 0) {
      final end = line.indexOf('*/', start + 2);
      if (end >= 0) {
        out.writeln(
          _withoutLineComment(
            line.substring(0, start) + line.substring(end + 2),
          ),
        );
      } else {
        block = true;
        out.writeln(_withoutLineComment(line.substring(0, start)));
      }
      continue;
    }
    out.writeln(_withoutLineComment(line));
  }
  return out.toString();
}

int _blockStart(String line) {
  final codeEnd = _lineCommentIndex(line);
  final code = codeEnd < 0 ? line : line.substring(0, codeEnd);
  var quote = '';
  for (var i = 0; i < code.length; i++) {
    if (quote.isNotEmpty) {
      if (code.startsWith(quote, i)) {
        i += quote.length - 1;
        quote = '';
      }
      continue;
    }
    if (code.startsWith("'''", i) || code.startsWith('"""', i)) {
      quote = code.substring(i, i + 3);
      i += 2;
      continue;
    }
    if (code[i] == "'" || code[i] == '"') {
      quote = code[i];
      continue;
    }
    if (code.startsWith('/*', i)) return i;
  }
  return -1;
}

String _withoutLineComment(String line) {
  final index = _lineCommentIndex(line);
  return index < 0 ? line : line.substring(0, index);
}

int _lineCommentIndex(String line) {
  var quote = '';
  for (var i = 0; i < line.length; i++) {
    if (quote.isNotEmpty) {
      if (line.startsWith(quote, i)) {
        i += quote.length - 1;
        quote = '';
      } else if (quote.length == 1 && line[i] == '\\') {
        i++;
      }
      continue;
    }
    if (line.startsWith("'''", i) || line.startsWith('"""', i)) {
      quote = line.substring(i, i + 3);
      i += 2;
      continue;
    }
    if (line[i] == "'" || line[i] == '"') {
      quote = line[i];
      continue;
    }
    if (line.startsWith('//', i)) return i;
  }
  return -1;
}
