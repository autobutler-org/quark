import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The rule this file exists to keep (#2254): an app bar's refresh is a slot,
/// not an action. It goes through `QuarkAppBar`/`QuarkPageScaffold`'s
/// `onRefresh` + `isRefreshing`, which renders it beside the brand button
/// where Files has always kept it. A refresh button dropped into `actions:`
/// lands somewhere different on every page, and two of them used a raw
/// `IconButton` with no spinner.
///
/// A phone's compact bar leaves the slot out (#4150), so a page that hands
/// the bar a refresh also pulls to refresh with a `RefreshIndicator`, unless
/// it is listed below with the reason it does not.
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

  /// Pages whose bar takes a refresh but whose body does not pull to
  /// refresh, each with the reason. All of them refresh on resume and on the
  /// app's interval, through `AutoRefreshMixin`.
  const noPull = {
    // Hands Files' refresh through; the page's listing pulls.
    'lib/widgets/file_browser/file_top_bar.dart',
    // A week or month grid, not a list, and reminders arrive as events.
    'lib/pages/calendar_page.dart',
    // Messages arrive live over the event stream.
    'lib/pages/chat_page.dart',
    // Tabs in a page view, each list a level below what a pull can reach.
    'lib/pages/system_page.dart',
    'lib/pages/users_page.dart',
    // The locked, set-up and error states are forms, not lists.
    'lib/pages/vault_page.dart',
  };

  test('a page whose bar refreshes also pulls to refresh on a phone', () {
    final bar = RegExp(r'\b(QuarkAppBar|QuarkPageScaffold)\(');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (noPull.contains(entity.path)) continue;
      final source = entity.readAsStringSync();
      if (source.contains('RefreshIndicator(')) continue;
      for (final match in bar.allMatches(source)) {
        final args = balancedArgs(source, match.end - 1);
        if (!passesOnRefresh(args)) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${entity.path}:${line + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A phone app bar has no refresh button (#4150). Wrap the list in '
          'RefreshIndicator(onRefresh: manualRefresh, ...).',
    );
  });
}

/// The source of the call arguments opening at [open], which indexes its
/// `(`, nested brackets included.
String balancedArgs(String source, int open) {
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

/// Whether the call [args] pass `onRefresh:` themselves, not through a
/// nested widget such as the page body.
bool passesOnRefresh(String args) {
  var depth = 0;
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 1 && args.startsWith('onRefresh:', i)) return true;
  }
  return false;
}
