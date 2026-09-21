import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule this file exists to keep (#2254): an app bar's refresh is a slot,
/// not an action. It goes through `QuarkAppBar`/`QuarkPageScaffold`'s
/// `onRefresh` + `isRefreshing`, which renders it beside the brand button
/// where Files has always kept it. A refresh button dropped into `actions:`
/// lands somewhere different on every page, and two of them used a raw
/// `IconButton` with no spinner.
void main() {
  final refreshInActions = RegExp(
    r'RefreshIconButton\(|QuarkIcons\.refresh\b|QuarkIcons\.refresh_rounded\b'
    r'|Icons\.refresh\b|Icons\.refresh_rounded\b',
  );

  /// The source of the `actions: [...]` list starting at [open], which indexes
  /// its `[`, or null when the brackets never balance.
  String? actionsList(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final c = source[i];
      if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
      }
    }
    return null;
  }

  test('no app bar builds its refresh button as an action', () {
    final offenders = <String>[];
    final actionsStart = RegExp(r'\bactions:\s*(const\s*)?\[');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in actionsStart.allMatches(source)) {
        final list = actionsList(source, match.end - 1);
        if (list == null || !refreshInActions.hasMatch(list)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${entity.path}:${line + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Pass onRefresh: manualRefresh and isRefreshing: isRefreshing to '
          'QuarkAppBar or QuarkPageScaffold instead of putting a refresh '
          'button in actions.',
    );
  });
}
