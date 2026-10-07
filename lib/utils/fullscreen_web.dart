import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: whether the browser allows the page to go fullscreen.
bool fullscreenSupported() => web.document.fullscreenEnabled;

/// Web: whether some element of the page is fullscreen.
bool fullscreenActive() => web.document.fullscreenElement != null;

/// Web: puts the whole page fullscreen, or leaves it.
Future<void> setFullscreenActive(bool active) async {
  if (!fullscreenSupported() || active == fullscreenActive()) return;
  try {
    if (active) {
      await web.document.documentElement?.requestFullscreen().toDart;
    } else {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {
    // Refused — no user gesture behind it, or a frame without permission.
    // The page stays as it was, which is what isActive will report.
  }
}
