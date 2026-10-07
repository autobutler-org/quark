import 'package:flutter/widgets.dart';

/// Whether the user has asked for less motion, on any platform.
///
/// True when either `MediaQuery.disableAnimationsOf` (Android's "Remove
/// animations", the browser's `prefers-reduced-motion`) or the platform's
/// `accessibilityFeatures.reduceMotion` (iOS Reduce Motion, which does not
/// set the `MediaQuery` flag) is on. Neither alone covers every platform.
///
/// The `MediaQuery` half registers a dependency on [context], so a widget
/// that reads this in `build` rebuilds when it changes. The platform half
/// does not: a widget that has to follow it live also listens to
/// `WidgetsBindingObserver.didChangeAccessibilityFeatures`, as `QuarkLoader`
/// does. A one-off read in a handler, to jump rather than animate, needs
/// neither.
///
/// ```dart
/// reduceMotionOf(context)
///     ? controller.jumpToPage(page)
///     : controller.animateToPage(page, duration: d, curve: Curves.easeOut);
/// ```
bool reduceMotionOf(BuildContext context) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
