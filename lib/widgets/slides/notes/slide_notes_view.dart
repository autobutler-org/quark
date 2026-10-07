import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slide's speaker notes, read-only, for the presenter view (#1166). Long
/// notes scroll; a slide without any says so.
///
/// Key prefixes: `slide_notes_view` on the scrolling text.
///
/// ```dart
/// SlideNotesView(notes: slide.notes);
/// ```
class SlideNotesView extends StatelessWidget {
  /// Shows [notes].
  const SlideNotesView({required this.notes, super.key});

  /// The notes, plain text; empty when the slide has none.
  final String notes;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final style = Theme.of(context).textTheme.bodyLarge;
    if (notes.trim().isEmpty) {
      return Text(
        'No notes for this slide.',
        style: style?.copyWith(color: tokens.mutedForeground),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('slide_notes_view'),
      child: Text(notes, style: style?.copyWith(color: tokens.foreground)),
    );
  }
}
