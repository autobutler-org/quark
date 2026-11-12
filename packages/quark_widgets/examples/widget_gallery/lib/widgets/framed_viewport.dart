import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Renders [child] as if the window were [width] by [height].
///
/// Layout widgets that read the window rather than their own constraints, such
/// as [QuarkSplitView], cannot otherwise be shown in both of their layouts on
/// one page.
class FramedViewport extends StatelessWidget {
  /// Frames [child] at [width] by [height].
  const FramedViewport({
    required this.width,
    required this.child,
    this.height = 280,
    super.key,
  });

  /// The window width the child is told about, and the width it is given.
  final double width;

  /// The window height the child is told about, and the height it is given.
  final double height;

  /// The widget under test.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: tokens.border)),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: Size(width, height), padding: EdgeInsets.zero),
          child: child,
        ),
      ),
    );
  }
}
