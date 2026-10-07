import 'package:quark/utils/fullscreen_stub.dart'
    if (dart.library.js_interop) 'package:quark/utils/fullscreen_web.dart';

/// Switches the app in and out of fullscreen, where the platform lets it:
/// the browser's Fullscreen API on the web, and immersive mode — the status
/// and navigation bars hidden — on Android and iOS. Desktop builds have no
/// switch, and [isSupported] is false there.
///
/// Presenting slides (#1165) toggles it on F. A test passes a fake in its
/// place.
///
/// ```dart
/// const screen = FullscreenControl();
/// if (screen.isSupported) await screen.setActive(!screen.isActive);
/// ```
class FullscreenControl {
  /// The platform's fullscreen.
  const FullscreenControl();

  /// Whether this platform can go fullscreen at all.
  bool get isSupported => fullscreenSupported();

  /// Whether the app is fullscreen now. On the web the user can leave by
  /// pressing Escape in the browser, so this asks every time.
  bool get isActive => fullscreenActive();

  /// Enters fullscreen when [active] is true and leaves it otherwise. Does
  /// nothing where [isSupported] is false.
  Future<void> setActive(bool active) => setFullscreenActive(active);
}
