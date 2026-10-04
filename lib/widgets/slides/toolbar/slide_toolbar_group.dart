import 'package:flutter/widgets.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';

/// The groups of the slide editor's contextual formatting row, in order:
/// the registry the wide row and the phone "Format" menu both read.
///
/// Each group shows only when [appliesTo] the selection — the text groups
/// for a text box or an open editing session, the shape group for shapes
/// and lines, arrange for any element — so the row is driven by what is
/// selected. On a phone each group is a submenu of "Format" named [label].
///
/// This is the seam for commands the `quark_slides` package grows: aligning
/// and distributing, grouping, and the clipboard (#1174, #1175) each become
/// a value here, the choices they offer a getter on [SlideToolbarActions],
/// and a case in `SlideFormatGroupControls` and `SlidePhoneFormatMenu`.
///
/// Key prefixes: `slide_format_group_<name>` on each group's run of
/// controls in the wide row, and on its submenu on a phone.
enum SlideToolbarGroup {
  /// Font family, size, bold, italic, underline, strikethrough and color.
  text('Text', QuarkIcons.format_menu),

  /// Alignment and lists.
  paragraph('Paragraph', QuarkIcons.format_align_left),

  /// Fill, outline color, width and dash, corner radius and opacity.
  shape('Shape', QuarkIcons.format_fill),

  /// Stacking order, duplicate and delete.
  arrange('Arrange', QuarkIcons.arrange);

  const SlideToolbarGroup(this.label, this.icon);

  /// The group's name in the phone menu.
  final String label;

  /// The group's glyph in the phone menu.
  final IconData icon;

  /// The group's key.
  String get key => 'slide_format_group_$name';

  /// Whether the group has anything to offer for [actions]' selection.
  bool appliesTo(SlideToolbarActions actions) => switch (this) {
    text || paragraph => actions.canFormatText,
    shape => actions.canStyle,
    arrange => actions.hasSelection,
  };
}
