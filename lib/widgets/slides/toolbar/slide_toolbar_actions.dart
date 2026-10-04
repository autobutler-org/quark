import 'package:flutter/widgets.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';

/// What the slide editor's toolbar offers, as [SlideToolbarChoice]s and
/// [SlideColorChoice]s built from [controller]'s state: the tools, the
/// text, paragraph and shape formatting the selection allows, and the
/// arrange commands. The wide rows and the phone menus draw the same
/// choices.
///
/// Every choice acts through [controller], so each is one undo step on the
/// document and starts the autosave.
///
/// Keys: the tools are `slide_tool_select`, `slide_tool_text`,
/// `slide_tool_shape_<kind>`, `slide_tool_line` and `slide_tool_arrow`; the
/// picture sources `slide_image_device` and `slide_image_quark`. Formatting
/// is `slide_format_<name>` (`bold`, `align_center`, `list_bullet`,
/// `font_<family>`, `font_default`, `stroke_width_<n>`, `dash_<name>`,
/// `opacity_<percent>`, `corner_<n>`), and the colors `slide_text_color`,
/// `slide_fill` and `slide_stroke_color`. Arrange is `slide_arrange_<move>`,
/// `slide_duplicate` and `slide_delete`.
class SlideToolbarActions {
  /// The toolbar for [controller]; [onImageFromDevice] and
  /// [onImageFromQuark] start the page's picture pickers.
  SlideToolbarActions(
    this.controller, {
    this.onImageFromDevice,
    this.onImageFromQuark,
  });

  /// The editor the toolbar acts on.
  final SlideEditorController controller;

  /// Picks a picture on this device to put on the slide.
  final VoidCallback? onImageFromDevice;

  /// Picks a picture already on the Quark to put on the slide.
  final VoidCallback? onImageFromQuark;

  SlideTextEditingController get _text => controller.textEditing;
  SlideCanvasTool get _tool => controller.tools.tool;

  // ── Tools ─────────────────────────────────────────────────────────────────

  SlideToolbarChoice _toolChoice(
    String key,
    SlideCanvasTool tool,
    IconData icon,
  ) => SlideToolbarChoice(
    key: key,
    label: defaultSlideToolLabel(tool),
    icon: icon,
    selected: _tool == tool,
    onSelected: () => controller.useTool(tool),
  );

  /// The pointer: select, move and resize.
  SlideToolbarChoice get select => _toolChoice(
    'slide_tool_select',
    SlideCanvasTool.select,
    QuarkIcons.select_tool,
  );

  /// Draw a text box.
  SlideToolbarChoice get text =>
      _toolChoice('slide_tool_text', SlideCanvasTool.text, QuarkIcons.text_box);

  /// Draw a line.
  SlideToolbarChoice get line =>
      _toolChoice('slide_tool_line', SlideCanvasTool.line, QuarkIcons.line);

  /// Draw an arrow.
  SlideToolbarChoice get arrow => _toolChoice(
    'slide_tool_arrow',
    SlideCanvasTool.arrowLine,
    QuarkIcons.arrow_line,
  );

  /// Draw each kind of shape.
  List<SlideToolbarChoice> get shapes => [
    for (final kind in ShapeKind.values)
      SlideToolbarChoice(
        key: 'slide_tool_shape_${kind.name}',
        label: _capitalized(shapeKindName(kind)),
        selected: _tool == SlideCanvasTool.shape(kind),
        onSelected: () => controller.useTool(SlideCanvasTool.shape(kind)),
      ),
  ];

  /// Whether a shape tool is the active one, which lights the shape menu.
  bool get shapeToolActive => _tool.mode == SlideToolMode.shape;

  /// Where a picture comes from.
  List<SlideToolbarChoice> get imageSources => [
    SlideToolbarChoice(
      key: 'slide_image_device',
      label: 'From this device',
      icon: QuarkIcons.upload_rounded,
      onSelected: controller.imageUpload == null ? onImageFromDevice : null,
    ),
    SlideToolbarChoice(
      key: 'slide_image_quark',
      label: 'From your Quark',
      icon: QuarkIcons.folder_outlined,
      onSelected: controller.imageUpload == null ? onImageFromQuark : null,
    ),
  ];

  // ── Text ──────────────────────────────────────────────────────────────────

  /// Whether a text box is selected or being edited.
  bool get canFormatText => _text.canFormat;

  TextFormat get _format => _text.selectionFormat;

  VoidCallback? _formatting(TextFormat format) =>
      canFormatText ? () => _text.format(format) : null;

  /// The family the selection shares, as the family menu reads it.
  String get fontFamilyLabel => switch (_format.fontFamily) {
    final String family => family,
    null => 'Default font',
    _ => 'Mixed fonts',
  };

  /// The default family, then each the app offers.
  List<SlideToolbarChoice> get fontFamilies => [
    SlideToolbarChoice(
      key: 'slide_format_font_default',
      label: 'Default font',
      selected: _format.fontFamily == null,
      onSelected: _formatting(const TextFormat(fontFamily: null)),
    ),
    for (final family in _text.fontFamilies)
      SlideToolbarChoice(
        key: 'slide_format_font_$family',
        label: family,
        selected: _format.fontFamily == family,
        onSelected: _formatting(TextFormat(fontFamily: family)),
      ),
  ];

  /// The size the selection shares, as the stepper reads it; empty when it
  /// is mixed.
  String get fontSizeLabel {
    final size = controller.fontSize;
    if (size == null) return '';
    return size == size.roundToDouble()
        ? '${size.round()}'
        : size.toStringAsFixed(1);
  }

  /// One size smaller.
  SlideToolbarChoice get fontSmaller => SlideToolbarChoice(
    key: 'slide_format_font_smaller',
    label: 'Smaller text',
    icon: QuarkIcons.remove,
    onSelected:
        canFormatText &&
            (controller.fontSize ?? double.infinity) >
                SlideEditorController.minFontSize
        ? () => controller.stepFontSize(-1)
        : null,
  );

  /// One size larger.
  SlideToolbarChoice get fontLarger => SlideToolbarChoice(
    key: 'slide_format_font_larger',
    label: 'Larger text',
    icon: QuarkIcons.add,
    onSelected:
        canFormatText &&
            (controller.fontSize ?? 0) < SlideEditorController.maxFontSize
        ? () => controller.stepFontSize(1)
        : null,
  );

  SlideToolbarChoice _toggle(
    TextToggle toggle,
    String key,
    String label,
    IconData icon,
  ) => SlideToolbarChoice(
    key: 'slide_format_$key',
    label: label,
    icon: icon,
    selected: toggle.isOn(_format),
    onSelected: canFormatText ? () => _text.toggle(toggle) : null,
  );

  /// Bold, italic, underline and strikethrough.
  List<SlideToolbarChoice> get textToggles => [
    _toggle(TextToggle.bold, 'bold', 'Bold', QuarkIcons.format_bold),
    _toggle(TextToggle.italic, 'italic', 'Italic', QuarkIcons.format_italic),
    _toggle(
      TextToggle.underline,
      'underline',
      'Underline',
      QuarkIcons.format_underlined,
    ),
    _toggle(
      TextToggle.strikethrough,
      'strikethrough',
      'Strikethrough',
      QuarkIcons.format_strikethrough,
    ),
  ];

  /// The text's color, or the theme's.
  SlideColorChoice get textColor => SlideColorChoice(
    key: 'slide_text_color',
    label: 'Text color',
    icon: QuarkIcons.format_text_color,
    current: _format.color is SlideColor ? _format.color as SlideColor : null,
    noneLabel: 'Default color',
    onChanged: canFormatText
        ? (color) => _text.format(TextFormat(color: color))
        : null,
  );

  // ── Paragraph ─────────────────────────────────────────────────────────────

  /// Left, center, right and justified.
  List<SlideToolbarChoice> get alignments => [
    for (final (alignment, label, icon) in [
      (TextAlignment.start, 'Align left', QuarkIcons.format_align_left),
      (TextAlignment.center, 'Align center', QuarkIcons.format_align_center),
      (TextAlignment.end, 'Align right', QuarkIcons.format_align_right),
      (TextAlignment.justify, 'Justify', QuarkIcons.format_align_justify),
    ])
      SlideToolbarChoice(
        key: 'slide_format_align_${alignment.name}',
        label: label,
        icon: icon,
        selected: _format.alignment == alignment,
        onSelected: _formatting(TextFormat(alignment: alignment)),
      ),
  ];

  /// Bulleted and numbered lists.
  List<SlideToolbarChoice> get lists => [
    _toggle(
      TextToggle.bulletList,
      'list_bullet',
      'Bulleted list',
      QuarkIcons.format_list_bulleted,
    ),
    _toggle(
      TextToggle.numberedList,
      'list_numbered',
      'Numbered list',
      QuarkIcons.format_list_numbered,
    ),
  ];

  // ── Shape ─────────────────────────────────────────────────────────────────

  /// Whether a shape or line is selected.
  bool get canStyle => controller.hasShapesOrLines;

  ElementStyle get _style => controller.selectionStyle;

  bool get _hasShapes =>
      controller.selectedElements.any((e) => e is ShapeElement);

  VoidCallback? _styling(ElementStyle style) =>
      canStyle ? () => controller.styleSelection(style) : null;

  /// A shape's fill, or none.
  SlideColorChoice get fill => SlideColorChoice(
    key: 'slide_fill',
    label: 'Fill color',
    icon: QuarkIcons.format_fill,
    current: _style.fill is SlideColor ? _style.fill as SlideColor : null,
    noneLabel: 'No fill',
    onChanged: _hasShapes
        ? (color) => controller.styleSelection(ElementStyle(fill: color))
        : null,
  );

  /// The outline's color; none removes a shape's outline.
  SlideColorChoice get strokeColor => SlideColorChoice(
    key: 'slide_stroke_color',
    label: 'Outline color',
    icon: QuarkIcons.stroke_color,
    current: _style.stroke == null ? null : _style.strokeColor,
    noneLabel: 'No outline',
    onChanged: canStyle
        ? (color) => controller.styleSelection(
            color == null
                ? const ElementStyle(stroke: null)
                : ElementStyle(strokeColor: color),
          )
        : null,
  );

  /// The outline widths offered, in slide units.
  static const strokeWidthValues = <double>[1, 2, 4, 8, 12, 16, 24];

  /// The outline's width.
  List<SlideToolbarChoice> get strokeWidths => [
    for (final width in strokeWidthValues)
      SlideToolbarChoice(
        key: 'slide_format_stroke_width_${width.round()}',
        label: '${width.round()} pt',
        selected: _style.strokeWidth == width,
        onSelected: _styling(ElementStyle(strokeWidth: width)),
      ),
  ];

  /// The outline's pattern.
  List<SlideToolbarChoice> get dashes => [
    for (final (dash, label) in [
      (StrokeDash.solid, 'Solid'),
      (StrokeDash.dash, 'Dashed'),
      (StrokeDash.dot, 'Dotted'),
      (StrokeDash.dashDot, 'Dash and dot'),
    ])
      SlideToolbarChoice(
        key: 'slide_format_dash_${dash.name}',
        label: label,
        selected: _style.dash == dash,
        onSelected: _styling(ElementStyle(dash: dash)),
      ),
  ];

  /// The corner radii offered for a rounded rectangle, in slide units; null
  /// is the proportional default.
  static const cornerRadiusValues = <double?>[null, 0, 12, 24, 48, 96];

  /// A rounded rectangle's corner radius; only offered with one selected.
  List<SlideToolbarChoice> get cornerRadii {
    final rounded = controller.selectedElements.any(
      (e) => e is ShapeElement && e.kind == ShapeKind.roundedRectangle,
    );
    return [
      for (final radius in cornerRadiusValues)
        SlideToolbarChoice(
          key: 'slide_format_corner_${radius?.round() ?? 'auto'}',
          label: radius == null ? 'Automatic' : '${radius.round()}',
          selected: _style.cornerRadius == radius,
          onSelected: rounded
              ? () => controller.styleSelection(
                  ElementStyle(cornerRadius: radius),
                )
              : null,
        ),
    ];
  }

  /// The opacities offered, as a share of opaque.
  static const opacityValues = <double>[1, 0.75, 0.5, 0.25];

  /// The whole element's opacity.
  List<SlideToolbarChoice> get opacities => [
    for (final opacity in opacityValues)
      SlideToolbarChoice(
        key: 'slide_format_opacity_${(opacity * 100).round()}',
        label: '${(opacity * 100).round()}%',
        selected: _style.opacity == opacity,
        onSelected: _styling(ElementStyle(opacity: opacity)),
      ),
  ];

  // ── Arrange ───────────────────────────────────────────────────────────────

  /// Whether anything is selected.
  bool get hasSelection => controller.selectedElementIds.isNotEmpty;

  VoidCallback? _whenSelected(VoidCallback action) =>
      hasSelection ? action : null;

  /// To front, forward, backward and to back.
  List<SlideToolbarChoice> get arrange => [
    for (final (move, label, icon) in [
      (ZOrderMove.toFront, 'Bring to front', QuarkIcons.bring_forward),
      (ZOrderMove.forward, 'Bring forward', QuarkIcons.bring_forward),
      (ZOrderMove.backward, 'Send backward', QuarkIcons.send_backward),
      (ZOrderMove.toBack, 'Send to back', QuarkIcons.send_backward),
    ])
      SlideToolbarChoice(
        key: 'slide_arrange_${move.name}',
        label: label,
        icon: icon,
        onSelected: _whenSelected(() => controller.arrange(move)),
      ),
  ];

  /// Copy the selection.
  SlideToolbarChoice get duplicate => SlideToolbarChoice(
    key: 'slide_duplicate',
    label: 'Duplicate',
    icon: QuarkIcons.content_copy,
    onSelected: _whenSelected(controller.duplicateSelection),
  );

  /// Delete the selection.
  SlideToolbarChoice get delete => SlideToolbarChoice(
    key: 'slide_delete',
    label: 'Delete',
    icon: QuarkIcons.delete_outline,
    onSelected: _whenSelected(controller.deleteSelection),
  );

  // ── Zoom (the phone's Format menu) ──────────────────────────────────────

  /// Zoom out, fit the slide (reading the zoom) and zoom in, for the phone,
  /// whose bar has no room for the wide row's zoom buttons.
  List<SlideToolbarChoice> get zoom => [
    SlideToolbarChoice(
      key: 'slide_menu_zoom_out',
      label: 'Zoom out',
      icon: QuarkIcons.zoom_out,
      onSelected: controller.canZoomOut ? controller.zoomOut : null,
    ),
    SlideToolbarChoice(
      key: 'slide_menu_zoom_fit',
      label: 'Fit slide (${controller.zoomPercent})',
      icon: QuarkIcons.fit_screen,
      onSelected: controller.zoomToFit,
    ),
    SlideToolbarChoice(
      key: 'slide_menu_zoom_in',
      label: 'Zoom in',
      icon: QuarkIcons.zoom_in,
      onSelected: controller.canZoomIn ? controller.zoomIn : null,
    ),
  ];

  static String _capitalized(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
