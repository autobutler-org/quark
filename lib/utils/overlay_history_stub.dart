import 'package:flutter/widgets.dart';

/// Pushes [route] on the navigator. Off the web there is no browser history
/// to keep in step.
Future<T?> pushWithBrowserBack<T>(BuildContext context, Route<T> route) {
  return Navigator.of(context).push<T>(route);
}
