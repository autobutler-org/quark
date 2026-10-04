import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native platforms: immersive mode on Android and iOS, nothing on desktop.
bool fullscreenSupported() =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

bool _active = false;

/// Whether immersive mode was last turned on here.
bool fullscreenActive() => _active;

/// Hides or restores the system bars.
Future<void> setFullscreenActive(bool active) async {
  if (!fullscreenSupported()) return;
  _active = active;
  await SystemChrome.setEnabledSystemUIMode(
    active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
}
