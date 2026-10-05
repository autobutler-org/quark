/// The pure functions behind the layout commands: building a slide's
/// placeholders, moving a slide onto another layout, and resetting it to
/// its own. `SlideDocumentController` wraps each in one undo step.
///
/// A placeholder inherits its layout's geometry until the user changes it:
/// a box whose frame is still exactly its slot's is re-flowed into the new
/// layout's slot, and one that was moved or resized keeps its frame. Its
/// anchor and paragraph alignment follow the same rule.
library;

import '../model/slide.dart';
import '../model/slide_element.dart';
import '../model/slide_size.dart';
import 'layout_placeholder.dart';
import 'slide_layout.dart';
import 'slide_master.dart';

/// [layout]'s placeholders as empty text boxes on a slide of [size], each
/// with an id from [newId].
List<TextBox> layoutBoxes(
  SlideLayout layout,
  SlideSize size,
  String Function() newId,
) =>
    [for (final p in layout.placeholders) p.emptyBox(newId(), size)];

/// [slide] moved onto [layout]: the slide's placeholder boxes fill
/// [layout]'s slots — by slot id first, then by text role — keeping their
/// text; a box left without a slot stays as an ordinary text box if it
/// has text and goes if it is empty; and each slot left unfilled gets an
/// empty box, at the back, with an id from [newId].
///
/// Only top-level boxes are placeholders. [master] supplies the slide's
/// current layout, to tell an untouched box from a moved one.
Slide applyLayout(
  Slide slide,
  SlideLayout layout,
  SlideSize size,
  String Function() newId, {
  SlideMaster master = SlideMaster.standard,
}) {
  final from = master.layoutById(slide.layoutId);
  final boxes = [
    for (final e in slide.elements)
      if (e is TextBox && e.slot != null) e,
  ];
  final slotOf = <String, LayoutPlaceholder>{}; // box id -> new slot
  bool claim(LayoutPlaceholder p, bool Function(TextBox) matches) {
    for (final box in boxes) {
      if (!slotOf.containsKey(box.id) && matches(box)) {
        slotOf[box.id] = p;
        return true;
      }
    }
    return false;
  }

  final open = [
    for (final p in layout.placeholders)
      if (!claim(p, (box) => box.slot == p.id)) p,
  ];
  final unfilled = [
    for (final p in open)
      if (!claim(p, (box) => box.textRole == p.role)) p,
  ];
  final elements = <SlideElement>[
    for (final p in unfilled) p.emptyBox(newId(), size),
    for (final e in slide.elements)
      if (e is! TextBox || e.slot == null)
        e
      else if (slotOf[e.id] case final p?)
        _reflow(e, from?.placeholder(e.slot), p, size)
      else if (e.plainText.trim().isNotEmpty)
        e.copyWith(slot: null, placeholder: ''),
  ];
  return slide.copyWith(layoutId: layout.id, elements: elements);
}

/// [slide] with its placeholders put back as its layout defines them: each
/// slot's box returns to the slot's frame, anchor and alignment, and its
/// runs drop their own size, family and color for the theme's; an empty
/// slot gets an empty box again, at the back, with an id from [newId].
/// Text, other elements and the background are left alone. A slide whose
/// layout [master] does not know is returned as it is.
Slide resetToLayout(
  Slide slide,
  SlideSize size,
  String Function() newId, {
  SlideMaster master = SlideMaster.standard,
}) {
  final layout = master.layoutById(slide.layoutId);
  if (layout == null) return slide;
  final filled = <String>{};
  final elements = [
    for (final e in slide.elements)
      if (e is TextBox &&
          layout.placeholder(e.slot) != null &&
          filled.add(e.slot!))
        _reset(e, layout.placeholder(e.slot)!, size)
      else
        e,
  ];
  return slide.copyWith(
    elements: [
      for (final p in layout.placeholders)
        if (!filled.contains(p.id)) p.emptyBox(newId(), size),
      ...elements,
    ],
  );
}

/// [box] moved from slot [from] (`null` when unknown) into slot [to].
TextBox _reflow(
  TextBox box,
  LayoutPlaceholder? from,
  LayoutPlaceholder to,
  SlideSize size,
) =>
    box.copyWith(
      frame: from != null && box.frame == from.frameOn(size)
          ? to.frameOn(size)
          : box.frame,
      anchor: from != null && box.anchor == from.anchor ? to.anchor : null,
      paragraphs: [
        for (final p in box.paragraphs)
          from != null && p.alignment == from.alignment
              ? p.copyWith(alignment: to.alignment)
              : p,
      ],
      placeholder: to.prompt,
      slot: to.id,
      textRole: to.role,
    );

/// [box] put back as slot [p] defines it.
TextBox _reset(TextBox box, LayoutPlaceholder p, SlideSize size) =>
    box.copyWith(
      frame: p.frameOn(size),
      anchor: p.anchor,
      autoFit: TextAutoFit.shrink,
      placeholder: p.prompt,
      textRole: p.role,
      paragraphs: [
        for (final paragraph in box.paragraphs)
          paragraph.copyWith(
            alignment: p.alignment,
            runs: [
              for (final run in paragraph.runs)
                run.copyWith(fontSize: null, fontFamily: null, color: null),
            ],
          ),
      ],
    );
