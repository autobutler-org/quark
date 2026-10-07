import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/toolbar/slide_phone_format_menu.dart';
import 'package:quark/widgets/slides/toolbar/slide_phone_insert_menu.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';

/// The slide toolbar on a phone (#1167): the labeled "Insert" and "Format"
/// menus, which hold everything the wide `SlideToolbar`'s two rows do, with
/// "Theme", "Slide layout", "Properties" and "Keyboard shortcuts" at the
/// end of "Format". It sits in the bar's second row
/// beside the slide position, so a phone's slide keeps its height.
///
/// A view-only presentation has no "Insert" menu, and "Format" holds only
/// what still works.
///
/// It listens to [controller], its tools and its text editing session, so
/// the menus follow the selection.
///
/// Key prefixes: the menus' own (`slide_insert_menu`, `slide_format_menu`).
class SlidePhoneToolbar extends StatelessWidget {
  /// The menus for [controller].
  const SlidePhoneToolbar({
    required this.controller,
    required this.onImageFromDevice,
    required this.onImageFromQuark,
    required this.onOpenProperties,
    required this.onShowShortcuts,
    required this.onOpenTheme,
    required this.onOpenLayout,
    required this.onOpenTransition,
    required this.onFind,
    this.onShare,
    super.key,
  });

  /// Opens the theme picker sheet.
  final VoidCallback onOpenTheme;

  /// Opens the slide layout picker sheet.
  final VoidCallback onOpenLayout;

  /// Opens the transition picker sheet.
  final VoidCallback onOpenTransition;

  /// Opens the find bar.
  final VoidCallback onFind;

  /// Opens the share sheet; null leaves "Share" out of the "Format" menu.
  final VoidCallback? onShare;

  /// The open presentation.
  final SlideEditorController controller;

  /// Picks a picture on this device to insert.
  final VoidCallback onImageFromDevice;

  /// Picks a picture on the Quark to insert.
  final VoidCallback onImageFromQuark;

  /// Opens the properties sheet.
  final VoidCallback onOpenProperties;

  /// Opens the keyboard shortcuts dialog.
  final VoidCallback onShowShortcuts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!controller.isReadOnly) SlidePhoneInsertMenu(actions: actions),
          SlidePhoneFormatMenu(
            actions: actions,
            onOpenProperties: onOpenProperties,
            onShowShortcuts: onShowShortcuts,
            onOpenTheme: onOpenTheme,
            onOpenLayout: onOpenLayout,
            onOpenTransition: onOpenTransition,
            onFind: onFind,
            onShare: onShare,
            readOnly: controller.isReadOnly,
          ),
        ],
      );
    },
  );
}
