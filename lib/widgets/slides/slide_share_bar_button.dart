import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_share_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The [SlideShareButton] in the slide editor's bar, on a window wide enough
/// for it (#1170).
///
/// Below [QuarkAppBarBottom.collapseBreakpoint] the bar has no room for
/// another button, and "Share" is in the phone toolbar's labeled "Format"
/// menu instead (`slide_format_share`), so this leaves nothing there.
///
/// Key prefixes: `slide_editor_share` on the button, as [SlideShareButton].
class SlideShareBarButton extends StatelessWidget {
  /// The bar's Share action; [onPressed] opens the share sheet, null shows
  /// it disabled.
  const SlideShareBarButton({required this.onPressed, super.key});

  /// Opens the share sheet; null while nothing is open.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width < QuarkAppBarBottom.collapseBreakpoint
      ? const SizedBox.shrink()
      : SlideShareButton(onPressed: onPressed);
}
