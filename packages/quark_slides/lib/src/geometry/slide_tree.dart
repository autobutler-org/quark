import '../model/element_frame.dart';
import '../model/slide.dart';
import '../model/slide_element.dart';
import 'group_geometry.dart';

/// Finding elements at any depth of a [Slide]: inside groups as well as on
/// the slide itself, with their frames on the slide.
///
/// `Slide.elementById` and `Slide.elements` see only the top level, where a
/// group is one element; these see through groups, which is what editing a
/// grouped element needs. Plain Dart, so the controller can use it.
extension SlideTree on Slide {
  /// Every element on the slide and inside its groups, depth first and back
  /// to front: a group comes just before its children.
  Iterable<SlideElement> get allElements sync* {
    Iterable<SlideElement> walk(List<SlideElement> list) sync* {
      for (final e in list) {
        yield e;
        if (e is GroupElement) yield* walk(e.children);
      }
    }

    yield* walk(elements);
  }

  /// The element with [id] at any depth, or `null` when there is none.
  SlideElement? findElement(String id) {
    for (final e in allElements) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The groups holding [id], outermost first: empty for an element on the
  /// slide itself, `null` when [id] is nowhere on the slide.
  List<GroupElement>? ancestorsOf(String id) {
    List<GroupElement>? search(List<SlideElement> list, List<GroupElement> up) {
      for (final e in list) {
        if (e.id == id) return up;
        if (e is GroupElement) {
          final found = search(e.children, [...up, e]);
          if (found != null) return found;
        }
      }
      return null;
    }

    return search(elements, const []);
  }

  /// The group directly holding [id], or `null` when it is on the slide
  /// itself or nowhere.
  GroupElement? parentOf(String id) {
    final ancestors = ancestorsOf(id);
    return ancestors == null || ancestors.isEmpty ? null : ancestors.last;
  }

  /// The frame of [id] on the slide, through every group holding it, or
  /// `null` when [id] is nowhere on the slide.
  ElementFrame? frameOnSlide(String id) {
    final element = findElement(id);
    if (element == null) return null;
    return placeOnSlide(id, element.frame);
  }

  /// [frame], given in the space of the group holding [id], placed on the
  /// slide — the slide frame of a draft of [id] being edited.
  ElementFrame placeOnSlide(String id, ElementFrame frame) {
    final ancestors = ancestorsOf(id) ?? const [];
    var placed = frame;
    for (final group in ancestors.reversed) {
      placed = frameInParent(group.frame, placed);
    }
    return placed;
  }
}
