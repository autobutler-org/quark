import 'slide_layout.dart';

/// The family of [layouts] a presentation's slides are built on.
///
/// [standard] is the built-in master: [SlideLayout.title],
/// [SlideLayout.titleAndContent], [SlideLayout.sectionHeader],
/// [SlideLayout.twoContent] and [SlideLayout.blank], in picker order. The
/// master's colors and fonts are the presentation's `SlideTheme`, so a
/// layout carries geometry and text roles only.
///
/// ```dart
/// for (final layout in SlideMaster.standard.layouts) LayoutCard(layout);
/// final slideId = doc.insertSlideWithLayout(SlideLayout.title.id);
/// ```
class SlideMaster {
  /// Creates a master.
  const SlideMaster({
    required this.id,
    required this.name,
    required this.layouts,
  });

  /// A stable id.
  final String id;

  /// The name a picker shows.
  final String name;

  /// The layouts, in picker order.
  final List<SlideLayout> layouts;

  /// The built-in master.
  static const standard = SlideMaster(
    id: 'standard',
    name: 'Standard',
    layouts: [
      SlideLayout.title,
      SlideLayout.titleAndContent,
      SlideLayout.sectionHeader,
      SlideLayout.twoContent,
      SlideLayout.blank,
    ],
  );

  /// The layout with [id], or `null` when there is none — a layout a
  /// newer version added, say.
  SlideLayout? layoutById(String id) {
    for (final layout in layouts) {
      if (layout.id == id) return layout;
    }
    return null;
  }
}
