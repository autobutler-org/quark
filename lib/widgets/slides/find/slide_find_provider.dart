import 'package:flutter/widgets.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';

/// Hands the slide editor's [SlideFindController] down to whatever inside
/// the editor draws matches — the canvas, for its highlights — without
/// threading it through every widget in between. `SlideFindLayout` puts
/// one around the editor; a widget that reads it rebuilds as the find bar
/// changes.
///
/// ```dart
/// final find = SlideFindProvider.maybeOf(context);
/// SlideCanvas(
///   highlights: find?.highlights ?? const [],
///   currentHighlight: find?.current,
///   ...
/// );
/// ```
class SlideFindProvider extends InheritedNotifier<SlideFindController> {
  /// Provides [controller] to [child].
  const SlideFindProvider({
    required SlideFindController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The nearest find controller above [context], or null outside the
  /// editor; [context] rebuilds when it changes.
  static SlideFindController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlideFindProvider>()?.notifier;
}
