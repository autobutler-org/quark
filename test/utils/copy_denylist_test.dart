import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Products and libraries Quark is built on, which a user never has to know
/// about (#3778). Remote access is built into Quark, so naming the networking
/// product behind it sends a family member off to install or sign in to
/// something they do not need. The keyring names are the same mistake on a
/// desktop: they mean nothing on a phone, where the same copy shows (#3776).
///
/// Matched case-insensitively as whole words, so `ReminderPicker` is not
/// `derp`.
const List<String> _denylist = [
  'Tailscale',
  'tsnet',
  'Headscale',
  'WireGuard',
  'ZeroTier',
  'DERP',
  'libsecret',
  'gnome-keyring',
  'GNOME Keyring',
  'KWallet',
  'Secret Service',
];

/// Where user-facing copy is written as constants: every widget in the
/// package, and the app's whole error vocabulary.
const List<String> _copySources = [
  'packages/quark_widgets/lib',
  'lib/utils/error_text.dart',
];

void main() {
  test('no copy names a vendor or library', () {
    final patterns = [
      for (final name in _denylist)
        RegExp(r'\b' + RegExp.escape(name) + r'\b', caseSensitive: false),
    ];
    final offenders = <String>[];

    for (final file in _dartFiles(_copySources)) {
      for (final literal in stringLiterals(file.readAsStringSync())) {
        for (final pattern in patterns) {
          if (pattern.hasMatch(literal.text)) {
            offenders.add('${file.path}:${literal.line}: ${literal.text}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Say what the feature does ("remote access", "the system keyring") '
          'rather than naming the product behind it.',
    );
  });

  // The scan above is only as good as the lexer under it: a comment read as
  // a string would fail on the doc comments that explain this rule, and a
  // string read as a comment would let copy through.
  group('stringLiterals', () {
    List<String> texts(String source) =>
        stringLiterals(source).map((l) => l.text).toList();

    test('reads every quote style, and adjacent literals one by one', () {
      expect(
        texts(
          "const a = 'one' \"two\";\n"
          "const b = '''three''' r'four\\n';",
        ),
        ['one', 'two', 'three', r'four\n'],
      );
    });

    test('skips comments, and slashes inside a string are not one', () {
      expect(
        texts(
          '/// Tailscale\n'
          '// Tailscale\n'
          "/* Tailscale /* nested */ still */ const u = 'https://x/y';",
        ),
        ['https://x/y'],
      );
    });

    test('reads strings nested in an interpolation', () {
      expect(texts(r"""f('a ${g('Tailscale')} b');"""), [
        r"a ${g('Tailscale')} b",
        'Tailscale',
      ]);
    });

    test('an escaped quote does not end the string', () {
      expect(texts(r"""'you\'re' 'next'"""), [r"you\'re", 'next']);
    });

    test('reports the line a literal starts on', () {
      expect(stringLiterals("\n\nconst a = 'x';").single.line, 3);
    });

    test('catches a denylisted name in a fixture', () {
      expect(
        texts("const s = 'connected through ' 'Tailscale or another route.';"),
        contains('Tailscale or another route.'),
      );
    });
  });
}

Iterable<File> _dartFiles(List<String> paths) sync* {
  for (final path in paths) {
    if (FileSystemEntity.isDirectorySync(path)) {
      final files =
          Directory(path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      yield* files;
    } else {
      yield File(path);
    }
  }
}

/// A string literal in Dart source: its raw text between the quotes and the
/// line it starts on.
typedef StringLiteral = ({String text, int line});

/// Every string literal in [source], comments skipped.
///
/// A literal nested in an interpolation is reported on its own as well as
/// inside its parent's text. Good enough for scanning copy, not a parser.
List<StringLiteral> stringLiterals(String source) {
  final found = <(int, String)>[];
  var i = 0;

  // Reads code from [i] until an unmatched `}` (inside an interpolation) or
  // the end of the source.
  void code({required bool inInterpolation}) {
    var depth = 0;
    while (i < source.length) {
      final c = source[i];
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        i = end < 0 ? source.length : end;
      } else if (source.startsWith('/*', i)) {
        var nesting = 0;
        while (i < source.length) {
          if (source.startsWith('/*', i)) {
            nesting++;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            nesting--;
            i += 2;
            if (nesting == 0) break;
          } else {
            i++;
          }
        }
      } else if (c == "'" || c == '"') {
        final raw = i > 0 && source[i - 1] == 'r';
        final triple = source.startsWith(c * 3, i);
        final quote = triple ? c * 3 : c;
        final start = i;
        i += quote.length;
        final textStart = i;
        while (i < source.length && !source.startsWith(quote, i)) {
          if (!raw && source[i] == r'\') {
            i += 2;
          } else if (!raw && source.startsWith(r'${', i)) {
            i += 2;
            code(inInterpolation: true);
            i++; // the closing brace
          } else {
            i++;
          }
        }
        found.add((
          start,
          source.substring(textStart, i.clamp(0, source.length)),
        ));
        i += quote.length;
      } else if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        if (inInterpolation && depth == 0) return;
        depth--;
        i++;
      } else {
        i++;
      }
    }
  }

  code(inInterpolation: false);
  // Sorted by where each starts, so an outer literal precedes those nested in
  // its interpolations.
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [
    for (final (start, text) in found)
      (
        text: text,
        line: '\n'.allMatches(source.substring(0, start)).length + 1,
      ),
  ];
}
