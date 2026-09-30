import 'package:flutter/widgets.dart';

/// Whether the user has asked for reduced motion, by either route Flutter
/// exposes: `MediaQuery.disableAnimationsOf` (Android's "Remove animations",
/// the browser's `prefers-reduced-motion`) or the platform's
/// `accessibilityFeatures.reduceMotion` (iOS Reduce Motion, which does not set
/// the MediaQuery flag).
///
/// Reading it in `build` or `didChangeDependencies` rebuilds on a MediaQuery
/// change, but not on an iOS Reduce Motion change: a widget that holds the
/// answer re-reads it from `WidgetsBindingObserver.didChangeAccessibilityFeatures`,
/// as `QuarkLoader` does. A widget that reads it at the moment it starts an
/// animation, in a tap handler say, needs no observer.
///
/// ```dart
/// final duration = reduceMotionOf(context) ? Duration.zero : _slide;
/// ```
bool reduceMotionOf(BuildContext context) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
