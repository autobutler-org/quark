import 'package:flutter/widgets.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/theme/slide_theme_picker.dart';
import 'package:quark_slides/quark_slides.dart';

/// The [SlideThemePicker] wired to [controller] (#1163): the built-in
/// themes, the presentation's marked, and a pick applied as one undo step
/// that starts the autosave. The properties panel, the toolbar's Theme
/// menu and a phone's Theme sheet all show this one.
///
/// Key prefixes: the picker's.
class SlideThemeControl extends StatelessWidget {
  /// The theme picker for [controller]'s presentation.
  const SlideThemeControl({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  @override
  Widget build(BuildContext context) {
    final presentation = controller.presentation;
    return SlideThemePicker(
      themes: SlideThemes.all,
      current: controller.theme,
      size: presentation?.size ?? SlideSize.widescreen,
      onSelected: presentation == null ? null : controller.applyTheme,
    );
  }
}
