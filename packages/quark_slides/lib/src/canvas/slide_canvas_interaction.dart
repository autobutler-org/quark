/// What a person may do on an editing `SlideCanvas`: everything, select and
/// read only, or look only.
///
/// A view-only editor — a deck shared without edit rights, or one whose
/// save was refused — passes [selectOnly] instead of hiding the canvas from
/// pointers, so it keeps selection, copying and the screen reader's labels
/// while no gesture, key or in-place editor can change the document.
///
/// ```dart
/// SlideCanvas(
///   document: doc,
///   slideId: slideId,
///   interaction: canEdit
///       ? SlideCanvasInteraction.editable
///       : SlideCanvasInteraction.selectOnly,
/// );
/// ```
enum SlideCanvasInteraction {
  /// Every gesture, key, tool and in-place editor.
  editable,

  /// Select elements and table cells — by tap, marquee, Tab, Escape and a
  /// screen reader's tap — enter groups, copy with Ctrl or Cmd C, pan and
  /// zoom. Nothing moves, resizes, rotates, inserts, deletes, pastes or
  /// opens for editing; selected elements are outlined without handles.
  selectOnly,

  /// Pan and zoom only: nothing is selected, and a selection the caller
  /// passes is not drawn. Elements still read to a screen reader.
  viewOnly;

  /// Whether the document may be changed.
  bool get edits => this == editable;

  /// Whether elements may be selected.
  bool get selects => this != viewOnly;
}
