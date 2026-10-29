// cspell:words kwallet libtailscale
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #3778: user-facing copy must not name a networking vendor, its libraries,
/// or a desktop keyring product. The unreachable checklist used to name one,
/// and [Errors.keyringUnavailable] used to name two more on phones.
void main() {
  test('exported copy constants name no vendor or library', () {
    const forbidden = [
      'tailscale',
      'headscale',
      'tsnet',
      'wireguard',
      'kwallet',
      'gnome keyring',
      'gnome-keyring',
      'libtailscale',
      'tailnet',
    ];

    final copies = <String, List<String>>{};
    for (final file in _dartFiles(Directory('packages/quark_widgets/lib'))) {
      copies[file.path] = _copyTexts(file.readAsStringSync());
    }
    const errors = 'lib/utils/error_text.dart';
    copies[errors] = _copyTexts(File(errors).readAsStringSync());

    final all = copies.values.expand((texts) => texts).join('\n');
    expect(
      all,
      contains("Make sure you're on your home"),
      reason: 'the scan missed the unreachable checklist',
    );
    expect(
      all,
      contains('system keyring'),
      reason: 'the scan missed Errors.keyringUnavailable',
    );
    expect(
      all,
      contains('Finish setting up at home.'),
      reason: 'the scan missed the phone unreachable reasons',
    );

    final hits = <String>[];
    for (final entry in copies.entries) {
      for (final text in entry.value) {
        final lower = text.toLowerCase();
        for (final name in forbidden) {
          if (lower.contains(name)) {
            hits.add('${entry.key}: "$name" in "$text"');
          }
        }
      }
    }
    expect(hits, isEmpty);
  });
}

List<File> _dartFiles(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

/// String literals that are copy: `const String` and `const List<String>`
/// initializers, plus the string arguments of an enum.
List<String> _copyTexts(String source) {
  final code = _withoutLineComments(source);
  final texts = <String>[];

  final constant = RegExp(
    r'^[ \t]*(?:static[ \t]+)?const[ \t]+'
    r'(?:(?:String|List<String>)[ \t]+)?'
    r'[A-Za-z_]\w*[ \t]*=',
    multiLine: true,
  );
  for (final match in constant.allMatches(code)) {
    final end = _semicolonOutsideStrings(code, match.end);
    texts.add(_literals(code.substring(match.end, end)).join());
  }

  final enumeration = RegExp(
    r'^[ \t]*enum[ \t]+[A-Za-z_]\w*(?:<[^>\n]*>)?\s*\{',
    multiLine: true,
  );
  for (final match in enumeration.allMatches(code)) {
    final open = match.end - 1;
    final close = _matchingBrace(code, open);
    texts.addAll(_literals(code.substring(open + 1, close)));
  }
  return texts;
}

String _withoutLineComments(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//')) line,
].join('\n');

List<String> _literals(String source) => [
  for (final match in RegExp(
    r'''r?'(?:\\'|[^'])*'|r?"(?:\\"|[^"])*"''',
  ).allMatches(source))
    match
        .group(0)!
        .substring(
          match.group(0)!.startsWith('r') ? 2 : 1,
          match.group(0)!.length - 1,
        ),
];

int _semicolonOutsideStrings(String source, int start) {
  var quote = 0;
  for (var i = start; i < source.length; i++) {
    final unit = source.codeUnitAt(i);
    if (quote != 0) {
      if (unit == 0x5c) {
        i++;
        continue;
      }
      if (unit == quote) quote = 0;
      continue;
    }
    if (unit == 0x27 || unit == 0x22) {
      quote = unit;
      continue;
    }
    if (unit == 0x3b) return i;
  }
  return source.length;
}

int _matchingBrace(String source, int open) {
  var depth = 0;
  var quote = 0;
  for (var i = open; i < source.length; i++) {
    final unit = source.codeUnitAt(i);
    if (quote != 0) {
      if (unit == 0x5c) {
        i++;
        continue;
      }
      if (unit == quote) quote = 0;
      continue;
    }
    if (unit == 0x27 || unit == 0x22) {
      quote = unit;
      continue;
    }
    if (unit == 0x7b) depth++;
    if (unit == 0x7d) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length - 1;
}
