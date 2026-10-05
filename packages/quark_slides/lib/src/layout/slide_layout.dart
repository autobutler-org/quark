import '../model/slide_element.dart';
import '../model/text_paragraph.dart';
import '../theme/theme_text_role.dart';
import 'layout_placeholder.dart';

/// An arrangement of [placeholders] a slide is built on: a title slide, a
/// title over content, two columns.
///
/// A slide names its layout by [id] (`Slide.layoutId`). Its placeholder
/// text boxes take their geometry from the layout until the user moves or
/// resizes them, and their unset styles from the theme's text style of
/// their [LayoutPlaceholder.role]; see `SlideDocumentController.setSlideLayout`
/// and `resetSlideToLayout`. The built-in layouts are the constants here,
/// gathered in `SlideMaster.standard`.
class SlideLayout {
  /// Creates a layout.
  const SlideLayout({
    required this.id,
    required this.name,
    this.placeholders = const [],
  });

  /// A stable id, written to `.qslide` as a slide's `layout`.
  final String id;

  /// The name a layout picker shows.
  final String name;

  /// The slots, back to front.
  final List<LayoutPlaceholder> placeholders;

  /// The slot [slotId], or `null` when the layout has none.
  LayoutPlaceholder? placeholder(String? slotId) {
    for (final p in placeholders) {
      if (p.id == slotId) return p;
    }
    return null;
  }

  /// The id of [blank], which every slide without a layout has.
  static const blankId = 'blank';

  static const _titleBar = LayoutPlaceholder(
    id: 'title',
    role: ThemeTextRole.title,
    left: 0.06,
    top: 0.05,
    width: 0.88,
    height: 0.15,
    prompt: 'Click to add title',
    anchor: TextAnchor.middle,
  );

  /// A centered title and subtitle, for the first slide.
  static const title = SlideLayout(
    id: 'title',
    name: 'Title slide',
    placeholders: [
      LayoutPlaceholder(
        id: 'title',
        role: ThemeTextRole.title,
        left: 0.1,
        top: 0.28,
        width: 0.8,
        height: 0.24,
        prompt: 'Click to add title',
        anchor: TextAnchor.bottom,
        alignment: TextAlignment.center,
      ),
      LayoutPlaceholder(
        id: 'subtitle',
        role: ThemeTextRole.subtitle,
        left: 0.1,
        top: 0.55,
        width: 0.8,
        height: 0.14,
        prompt: 'Click to add subtitle',
        alignment: TextAlignment.center,
      ),
    ],
  );

  /// A title across the top over one content area.
  static const titleAndContent = SlideLayout(
    id: 'titleAndContent',
    name: 'Title and content',
    placeholders: [
      _titleBar,
      LayoutPlaceholder(
        id: 'body',
        role: ThemeTextRole.body,
        left: 0.06,
        top: 0.24,
        width: 0.88,
        height: 0.68,
        prompt: 'Click to add text',
      ),
    ],
  );

  /// A large title and a line of text, between sections.
  static const sectionHeader = SlideLayout(
    id: 'sectionHeader',
    name: 'Section header',
    placeholders: [
      LayoutPlaceholder(
        id: 'title',
        role: ThemeTextRole.title,
        left: 0.08,
        top: 0.34,
        width: 0.84,
        height: 0.22,
        prompt: 'Click to add section title',
        anchor: TextAnchor.bottom,
      ),
      LayoutPlaceholder(
        id: 'subtitle',
        role: ThemeTextRole.subtitle,
        left: 0.08,
        top: 0.58,
        width: 0.84,
        height: 0.12,
        prompt: 'Click to add text',
      ),
    ],
  );

  /// A title across the top over two side-by-side content areas.
  static const twoContent = SlideLayout(
    id: 'twoContent',
    name: 'Two content',
    placeholders: [
      _titleBar,
      LayoutPlaceholder(
        id: 'left',
        role: ThemeTextRole.body,
        left: 0.06,
        top: 0.24,
        width: 0.43,
        height: 0.68,
        prompt: 'Click to add text',
      ),
      LayoutPlaceholder(
        id: 'right',
        role: ThemeTextRole.body,
        left: 0.51,
        top: 0.24,
        width: 0.43,
        height: 0.68,
        prompt: 'Click to add text',
      ),
    ],
  );

  /// No placeholders.
  static const blank = SlideLayout(id: blankId, name: 'Blank');

  @override
  String toString() => 'SlideLayout($id)';
}
