import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/toolbar/slide_format_row.dart';
import 'package:quark/widgets/slides/toolbar/slide_tool_row.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's toolbar under the app bar (#1167).
///
/// At [QuarkAppBarBottom.collapseBreakpoint] and wider it is two rows: the
/// [SlideToolRow] of drawing tools and the picture menu, and the
/// [SlideFormatRow] of formatting for whatever is selected. Narrower — the
/// same breakpoint every page's second bar row folds at — it takes no room:
/// a phone's slide needs the height, so the rows fold into the labeled
/// "Insert" and "Format" menus of the `SlidePhoneToolbar` in the bar's
/// second row, never an anonymous overflow.
///
/// It listens to [controller], its tools and its text editing session, so
/// the toggles follow the selection and the caret. Every control acts
/// through [controller]: one undo step each, and the autosave.
///
/// Key prefixes: `slide_toolbar` on the toolbar; the rows' own.
class SlideToolbar extends StatelessWidget {
  /// The toolbar for [controller].
  const SlideToolbar({
    required this.controller,
    required this.onImageFromDevice,
    required this.onImageFromQuark,
    super.key,
  });

  /// The open presentation.
  final SlideEditorController controller;

  /// Picks a picture on this device to insert.
  final VoidCallback onImageFromDevice;

  /// Picks a picture on the Quark to insert.
  final VoidCallback onImageFromQuark;

  /// Whether a window [width] wide folds the toolbar into the phone menus.
  static bool isCompact(double width) =>
      width < QuarkAppBarBottom.collapseBreakpoint;

  /// The height of one row.
  static const double rowHeight = QuarkAppBarBottom.height;

  @override
  Widget build(BuildContext context) {
    if (isCompact(MediaQuery.sizeOf(context).width)) {
      return const SizedBox.shrink();
    }
    final tokens = QuarkTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.tools,
        controller.textEditing,
      ]),
      builder: (context, _) {
        final actions = SlideToolbarActions(
          controller,
          onImageFromDevice: onImageFromDevice,
          onImageFromQuark: onImageFromQuark,
        );
        return DecoratedBox(
          key: const ValueKey('slide_toolbar'),
          decoration: BoxDecoration(
            color: tokens.card,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: rowHeight),
                  child: SlideToolRow(
                    actions: actions,
                    propertiesOpen: controller.propertiesOpen,
                    onToggleProperties: controller.toggleProperties,
                  ),
                ),
                Divider(height: 1, color: tokens.border),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: rowHeight),
                  child: SlideFormatRow(actions: actions),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
