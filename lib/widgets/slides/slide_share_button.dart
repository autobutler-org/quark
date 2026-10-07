import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's bar action that opens the share sheet for the open
/// presentation (#1170): a share glyph explained by its tooltip, which a
/// screen reader announces too. The page passes `showShareSheet` for the
/// presentation's path as [onPressed]; a null [onPressed] shows it disabled.
///
/// Key prefixes: `slide_editor_share` on the button.
///
/// ```dart
/// SlideShareButton(onPressed: () => showShareSheet(context, ...));
/// ```
class SlideShareButton extends StatelessWidget {
  /// Creates the button.
  const SlideShareButton({
    required this.onPressed,
    super.key = const ValueKey('slide_editor_share'),
  });

  /// What the tooltip and a screen reader call the action.
  static const label = 'Share';

  /// Opens the share sheet; null while nothing is open.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => QuarkBarIconButton(
    icon: QuarkIcons.share_outlined,
    tooltip: label,
    onPressed: onPressed,
  );
}
