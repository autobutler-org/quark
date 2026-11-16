import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2311: every top bar action is a package bar button with a QuarkIcons
/// glyph. A bare `IconButton`, `TextButton` or `PopupMenuButton`, or a
/// Material `Icons.` glyph, in a bar's actions is how the same action ended
/// up with a different shape, size and icon on every page.
void main() {
  /// The bars whose `actions:` this test reads: the drawer pages' and every
  /// detail, editor and viewer page's.
  final bar = RegExp(
    r'\b(QuarkAppBar|QuarkPageScaffold|ChromeAppBar|AppBar'
    r'|FileRouteChrome|FileViewerChrome)\(',
  );

  /// Bars allowed an exception, each with the reason.
  const exempt = {
    // The trim mode's Save Clip and Cancel stay text buttons, as #2313 left
    // them; the rest of this bar follows the rule.
    'lib/pages/video_viewer_page.dart',
  };

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
      if (exempt.contains(entity.path)) continue;
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

  // #4150: the theme toggle, the connection pill, the jobs badge and the
  // bell are the app's. `AppBarTrailingHost` puts them on every wide bar and
  // in the account sheet on a phone, so a page that adds one shows it twice.
  test('no bar carries an app-wide control in its own actions', () {
    final appWide = RegExp(
      r'\b(AppThemeToggle|ThemeToggleButton|ConnectionSheetButton'
      r'|ConnectionIndicator|JobsBadge|NotificationsBell)\(',
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in bar.allMatches(source)) {
        final actions = actionsOf(balanced(source, match.end - 1));
        if (actions == null || !appWide.hasMatch(actions)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${entity.path}:${line + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'App-wide controls come from AppBarTrailingHost, not a page\'s '
          'actions.',
    );
  });

  // #4150: a phone's bar shows two page actions at most, and asserts when
  // given more. A page that writes more than two picks its phone pair with
  // QuarkAppBar.isCompact, as Photos does.
  test('a bar with more than two actions picks its phone pair', () {
    final mainBar = RegExp(r'\b(QuarkAppBar|QuarkPageScaffold)\(');

    /// The top-level entries of the list literal [list].
    int entries(String list) {
      var depth = 0;
      var count = 0;
      var pending = false;
      for (var i = 1; i < list.length - 1; i++) {
        // A comment's commas are not entries.
        if (list.startsWith('//', i)) {
          final end = list.indexOf('\n', i);
          i = end < 0 ? list.length : end;
          continue;
        }
        final c = list[i];
        if (c == '(' || c == '[' || c == '{') depth++;
        if (c == ')' || c == ']' || c == '}') depth--;
        if (depth == 0 && c == ',') {
          if (pending) count++;
          pending = false;
        } else if (c.trim().isNotEmpty) {
          pending = true;
        }
      }
      return count + (pending ? 1 : 0);
    }

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('QuarkAppBar.isCompact(')) continue;
      for (final match in mainBar.allMatches(source)) {
        final actions = actionsOf(balanced(source, match.end - 1));
        if (actions == null ||
            entries(actions) <= QuarkAppBar.compactMaxActions) {
          continue;
        }
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${entity.path}:${line + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Give a phone two actions at most: choose them with '
          'QuarkAppBar.isCompact and put the rest in a labeled menu.',
    );
  });
}
