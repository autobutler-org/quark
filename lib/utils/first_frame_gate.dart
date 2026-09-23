import 'package:flutter/widgets.dart';

/// Holds back [binding]'s first frame until [routerDelegate] reports its first
/// route.
///
/// go_router builds an empty `SizedBox` while an async redirect is still
/// resolving, and on a signed-out launch `authRedirect` asks the Quark whether
/// it has been set up before it can answer. Painting that empty frame fires
/// `flutter-first-frame`, which takes the web splash down onto a blank page
/// until the answer arrives. Deferring the frame keeps the splash up until
/// there is a page to show; on mobile the native launch screen stays up the
/// same way.
void deferFirstFrameUntilRouted(
  WidgetsBinding binding,
  Listenable routerDelegate,
) {
  binding.deferFirstFrame();
  void release() {
    routerDelegate.removeListener(release);
    binding.allowFirstFrame();
  }

  routerDelegate.addListener(release);
}
