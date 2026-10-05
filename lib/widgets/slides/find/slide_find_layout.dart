import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/find/slide_find_bar.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark/widgets/slides/find/slide_find_provider.dart';
import 'package:quark/widgets/slides/find/slide_find_shortcuts.dart';

/// The slide editor's body with find and replace around it: [child] above,
/// the [SlideFindBar] along the bottom while [controller] is open — just
/// above the keyboard on a phone, since the scaffold lifts the body over it
/// — and Ctrl or Cmd F and H opening it from anywhere inside. The bar
/// takes at most [maxBarFraction] of the height and scrolls past it.
/// [child] finds [controller] through [SlideFindProvider], which is how the
/// canvas inside draws the matches.
///
/// Key prefixes: those of [SlideFindBar].
///
/// ```dart
/// body: SlideFindLayout(controller: find, child: SlideEditorBody(...)),
/// ```
class SlideFindLayout extends StatelessWidget {
  /// Puts [controller]'s bar under [child].
  const SlideFindLayout({
    required this.controller,
    required this.child,
    super.key,
  });

  /// The find bar's state.
  final SlideFindController controller;

  /// The editor.
  final Widget child;

  /// The most of the height the bar takes; past it the bar scrolls, so a
  /// phone at a large text size keeps some of the slide in view.
  static const double maxBarFraction = 0.6;

  @override
  Widget build(BuildContext context) => SlideFindShortcuts(
    onFind: controller.open,
    onReplace: () => controller.open(replace: true),
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: SlideFindProvider(controller: controller, child: child),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * maxBarFraction,
            ),
            child: SlideFindBar(controller: controller),
          ),
        ],
      ),
    ),
  );
}
