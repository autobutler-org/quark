import 'package:flutter/widgets.dart';
import 'package:quark/utils/overlay_history_stub.dart'
    if (dart.library.js_interop) 'package:quark/utils/overlay_history_web.dart'
    as platform;

/// Pushes [route] and, on the web, a history entry at the current URL, so
/// browser Back closes the overlay instead of leaving the page (#2077).
///
/// The photo viewer is pushed with no history entry of its own, so Back was
/// returning to Files; the same URL keeps that Back on Photos.
Future<T?> pushWithBrowserBack<T>(BuildContext context, Route<T> route) {
  return platform.pushWithBrowserBack<T>(context, route);
}
