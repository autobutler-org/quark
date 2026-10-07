import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The speaker notes of the selected slide, under the slide editor's canvas
/// (#1166): a header that opens and closes the panel, and when open, a plain
/// multi-line field holding the notes.
///
/// Every change to the text goes out through [onChanged]; the editor holds
/// it for a pause and then writes it to the slide as one undo step. When
/// [notes] changes from outside — another slide shown, an undo — the field
/// takes the new text; while typing, [notes] is what was just typed, so the
/// field is left alone.
///
/// The field is [fieldHeight] tall and scrolls within it, so the caller can
/// keep it from crowding the canvas off a short screen.
///
/// Key prefixes: `slide_notes_toggle` on the header and `slide_notes_field`
/// on the text field.
///
/// ```dart
/// SlideNotesPanel(
///   slideId: c.selectedSlideId!,
///   notes: c.notes,
///   open: c.notesOpen,
///   onToggle: c.toggleNotes,
///   onChanged: c.editNotes,
/// );
/// ```
class SlideNotesPanel extends StatefulWidget {
  /// Creates the panel over the slide [slideId]'s [notes].
  const SlideNotesPanel({
    required this.slideId,
    required this.notes,
    required this.open,
    required this.onToggle,
    required this.onChanged,
    this.fieldHeight = maxFieldHeight,
    this.readOnly = false,
    super.key,
  });

  /// The slide the notes belong to.
  final String slideId;

  /// The notes, plain text.
  final String notes;

  /// Whether the field is showing.
  final bool open;

  /// Opens or closes the panel.
  final VoidCallback onToggle;

  /// Called with the whole text after every change.
  final ValueChanged<String> onChanged;

  /// How tall the field is.
  final double fieldHeight;

  /// Whether the notes can be read but not typed in, for a view-only
  /// presentation.
  final bool readOnly;

  /// The header's height: one touch target.
  static const double headerHeight = kMinInteractiveDimension;

  /// The field's height when there is room for it.
  static const double maxFieldHeight = 140;

  @override
  State<SlideNotesPanel> createState() => _SlideNotesPanelState();
}

class _SlideNotesPanelState extends State<SlideNotesPanel> {
  late final _text = TextEditingController(text: widget.notes);

  @override
  void didUpdateWidget(SlideNotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notes != _text.text) _text.text = widget.notes;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final SlideNotesPanel(:open, :onToggle, :onChanged, :fieldHeight) = widget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: tokens.border),
        Semantics(
          button: true,
          expanded: open,
          label: 'Speaker notes',
          onTap: onToggle,
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('slide_notes_toggle'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SlideNotesPanel.headerHeight,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
                child: Row(
                  spacing: tokens.spacingSm,
                  children: [
                    Icon(QuarkIcons.notes_rounded, color: tokens.foreground),
                    Expanded(
                      child: Text(
                        'Speaker notes',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      open ? QuarkIcons.expand_more : QuarkIcons.expand_less,
                      color: tokens.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          SizedBox(
            height: fieldHeight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacingMd,
                0,
                tokens.spacingMd,
                tokens.spacingSm,
              ),
              child: TextField(
                key: const ValueKey('slide_notes_field'),
                controller: _text,
                onChanged: onChanged,
                readOnly: widget.readOnly,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: widget.readOnly
                      ? 'No speaker notes'
                      : 'Notes for the speaker, shown while presenting',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
