import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:quark/utils/startup_config.dart';

/// Holds back [binding]'s first frame until [routerDelegate] reports its first
/// route, or until [maxHold] has passed.
///
/// go_router builds an empty `SizedBox` while an async redirect is still
/// resolving, and on a signed-out launch `authRedirect` asks the Quark whether
/// it has been set up before it can answer. Painting that empty frame fires
/// `flutter-first-frame`, which takes the web splash down onto a blank page
/// until the answer arrives. Deferring the frame keeps the splash up until
/// there is a page to show; on mobile the native launch screen stays up the
/// same way.
///
/// [maxHold] bounds that wait: a redirect that never answers must not keep
/// the launch screen up for good (#2066). After it the frames go out, the
/// page appears whenever the router does route, and [onMaxHold] is called so
/// the launch can record that it waited the whole hold.
void deferFirstFrameUntilRouted(
  WidgetsBinding binding,
  Listenable routerDelegate, {
  Duration maxHold = StartupConfig.firstFrameMaxHold,
  VoidCallback? onMaxHold,
}) {
  binding.deferFirstFrame();
  late final Timer timer;
  // Runs once: routing cancels the timer, and the timer removes the listener.
  void release() {
    timer.cancel();
    routerDelegate.removeListener(release);
    binding.allowFirstFrame();
  }

  timer = Timer(maxHold, () {
    release();
    onMaxHold?.call();
  });
  routerDelegate.addListener(release);
}
