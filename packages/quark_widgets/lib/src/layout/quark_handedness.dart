import 'package:flutter/widgets.dart';

/// Says which hand the navigation controls are laid out for (#1812).
///
/// Under a left-handed scope `QuarkAppBar` puts its brand button at the far
/// end of the bar and its actions at the near one, and `QuarkPageScaffold`
/// slides the drawer in from that same edge and moves its floating button to
/// the other. Only the controls change sides: text and content keep the
/// direction they are read in.
///
/// The package cannot read app state, so the app provides this once, above
/// its pages, from its own setting. Without a scope nothing is mirrored,
/// which is what the gallery and tests see. A page that places a control of
/// its own against one edge asks [isLeftHanded] which edge that is.
///
/// It paints nothing and has no keys.
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => QuarkHandedness(
///     leftHanded: settings.leftHanded.value,
///     child: child!,
///   ),
/// );
/// ```
class QuarkHandedness extends InheritedWidget {
  /// Lays out the navigation controls below for the left hand when
  /// [leftHanded], and for the right hand otherwise.
  const QuarkHandedness({
    required this.leftHanded,
    required super.child,
    super.key,
  });

  /// Whether the controls below are mirrored for the left hand.
  final bool leftHanded;

  /// Whether [context] is under a left-handed scope. False with no scope.
  static bool isLeftHanded(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QuarkHandedness>()
          ?.leftHanded ??
      false;

  @override
  bool updateShouldNotify(QuarkHandedness oldWidget) =>
      oldWidget.leftHanded != leftHanded;
}
