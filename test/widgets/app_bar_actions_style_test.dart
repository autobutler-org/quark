import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #2311: every top bar action is a package bar button with a QuarkIcons
/// glyph. A bare `IconButton`, `TextButton` or `PopupMenuButton`, or a
/// Material `Icons.` glyph, in a bar's actions is how the same action ended
/// up with a different shape, size and icon on every page.
void main() {
  /// The bars whose `actions:` this test reads.
  final bar = RegExp(r'\b(QuarkAppBar|QuarkPageScaffold)\(');

  final offender = RegExp(
    r'\bIconButton\(|\bTextButton(\.icon)?\(|\bFilledButton(\.icon)?\('
    r'|\bPopupMenuButton\b|(?<!Quark)\bIcons\.',
  );

  /// The source of the bracketed expression that opens at [open].
  String balanced(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final c = source[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') {
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
      }
    }
    return source.substring(open);
  }

  /// The `actions:` list passed directly to the call [args], ignoring any
  /// nested widget's own `actions:`.
  String? actionsOf(String args) {
    var depth = 0;
    for (var i = 0; i < args.length; i++) {
      final c = args[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth--;
      if (depth == 1 && args.startsWith('actions:', i)) {
        final open = args.indexOf('[', i);
        return open < 0 ? null : balanced(args, open);
      }
    }
    return null;
  }

  test('no bar builds its actions from Material buttons or icons', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in bar.allMatches(source)) {
        final actions = actionsOf(balanced(source, match.end - 1));
        if (actions == null || !offender.hasMatch(actions)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${entity.path}:${line + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Build bar actions from QuarkBarIconButton, QuarkBarChip or '
          'QuarkBarSegmentedToggle, with QuarkIcons glyphs.',
    );
  });
}
