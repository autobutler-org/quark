import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// One choice of a few, as a full-width segmented control in a form: muted
/// segments on the input fill, the picked one tinted with the primary color,
/// no check mark, and the standard density that keeps the 48dp touch target
/// (#2605).
///
/// This is the form control. A top bar's view switch is
/// `QuarkBarSegmentedToggle`.
///
/// Key prefixes: none of its own. The caller keys each segment's label, such
/// as `event_repeat_weekly`, so a `.probe` script can tap it.
///
/// ```dart
/// QuarkSegmentedChoice<bool>(
///   segments: const [
///     ButtonSegment(
///       value: false,
///       label: Text('Never', key: ValueKey('event_repeat_ends_never')),
///     ),
///     ButtonSegment(
///       value: true,
///       label: Text('On a date', key: ValueKey('event_repeat_ends_on')),
///     ),
///   ],
///   selected: until != null,
///   onChanged: setEnds,
/// );
/// ```
class QuarkSegmentedChoice<T> extends StatelessWidget {
  /// Creates the control with [selected] picked.
  const QuarkSegmentedChoice({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The choices, each labeled and keyed by the caller.
  final List<ButtonSegment<T>> segments;

  /// The value of the segment picked now.
  final T selected;

  /// Called with the value of the segment tapped.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return SegmentedButton<T>(
      segments: segments,
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.single),
      style: SegmentedButton.styleFrom(
        foregroundColor: tokens.secondaryForeground,
        backgroundColor: tokens.input,
        selectedForegroundColor: tokens.primary,
        selectedBackgroundColor: tokens.primary.withValues(alpha: 0.12),
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Standard density: any less and Material shrinks the 48dp touch
        // target with it (#2605).
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
