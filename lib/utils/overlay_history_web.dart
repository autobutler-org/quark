import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web: push a history entry at the current URL, and pop [route] when the
/// browser moves back off that entry.
Future<T?> pushWithBrowserBack<T>(BuildContext context, Route<T> route) {
  final navigator = Navigator.of(context);
  final history = web.window.history;
  // Same URL as the page already showing, so Back does not ask the router to
  // leave it. Keep the page's history state: an entry with none is not one of
  // the router's, and landing on it later makes the router navigate again.
  history.pushState(history.state, '', web.window.location.href);

  var movedByBrowser = false;
  final subscription = web.window.onPopState.listen((_) {
    // The browser already moved. Closing the route must not move again.
    movedByBrowser = true;
    if (navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
  });

  return navigator.push<T>(route).whenComplete(() async {
    // Cancel first. history.back() fires the same event, and the listener
    // must not treat that as another browser Back.
    await subscription.cancel();
    if (!movedByBrowser) {
      history.back();
    }
  });
}
