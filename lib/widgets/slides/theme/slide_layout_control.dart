import 'package:flutter/widgets.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/theme/slide_layout_picker.dart';
import 'package:quark_slides/quark_slides.dart';

/// The [SlideLayoutPicker] wired to [controller]'s selected slide (#1163):
/// a pick moves the slide onto that layout, keeping its text, and "Reset
/// slide to layout" puts its placeholders back; one undo step each. The
/// properties panel, the toolbar's Layout menu and a phone's Slide layout
/// sheet all show this one.
///
/// Key prefixes: the picker's, under `slide_layout`.
class SlideLayoutControl extends StatelessWidget {
  /// The layout picker for [controller]'s selected slide.
  const SlideLayoutControl({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  @override
  Widget build(BuildContext context) {
    final hasSlide = controller.selectedSlide != null;
    return SlideLayoutPicker(
      layouts: controller.layouts,
      currentLayoutId: controller.selectedLayoutId,
      size: controller.presentation?.size ?? SlideSize.widescreen,
      theme: controller.theme,
      onSelected: hasSlide ? controller.setSlideLayout : null,
      onReset: hasSlide ? controller.resetSlideToLayout : null,
    );
  }
}
