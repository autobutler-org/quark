import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/transition/slide_transition_labels.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slider for a transition's length, 200 to 2000 ms in steps of 100, with
/// the value beside it as a number (#1164). A drag reports its length once,
/// when it ends, so it is one undo step; a key press or a screen reader's
/// step reports at once.
///
/// Key prefixes: `slide_transition_duration` on the slider and
/// `slide_transition_duration_label` on the number.
class SlideTransitionDurationField extends StatefulWidget {
  /// The slider for [durationMs]; [onChanged] null disables it.
  const SlideTransitionDurationField({
    required this.durationMs,
    required this.onChanged,
    super.key,
  });

  /// The length in effect.
  final int durationMs;

  /// Called with the length when a drag ends or a key press steps it.
  final ValueChanged<int>? onChanged;

  @override
  State<SlideTransitionDurationField> createState() =>
      _SlideTransitionDurationFieldState();
}

class _SlideTransitionDurationFieldState
    extends State<SlideTransitionDurationField> {
  /// The length mid-drag, or null at rest.
  double? _dragging;

  /// Whether a drag is under way, so its steps are held back.
  bool _isDrag = false;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final value = (_dragging ?? widget.durationMs.toDouble()).clamp(
      SlideTransitionSpec.minDurationMs.toDouble(),
      SlideTransitionSpec.maxDurationMs.toDouble(),
    );
    final label = SlideTransitionLabels.duration(value.round());
    final onChanged = widget.onChanged;
    return Row(
      spacing: tokens.spacingSm,
      children: [
        Expanded(
          child: Slider(
            key: const ValueKey('slide_transition_duration'),
            value: value,
            min: SlideTransitionSpec.minDurationMs.toDouble(),
            max: SlideTransitionSpec.maxDurationMs.toDouble(),
            divisions:
                (SlideTransitionSpec.maxDurationMs -
                    SlideTransitionSpec.minDurationMs) ~/
                100,
            label: label,
            semanticFormatterCallback: (v) =>
                'Duration ${SlideTransitionLabels.duration(v.round())}',
            onChangeStart: (_) => _isDrag = true,
            onChanged: onChanged == null
                ? null
                : (v) => _isDrag
                      ? setState(() => _dragging = v)
                      : onChanged(v.round()),
            onChangeEnd: onChanged == null
                ? null
                : (v) {
                    _isDrag = false;
                    setState(() => _dragging = null);
                    onChanged(v.round());
                  },
          ),
        ),
        Text(
          label,
          key: const ValueKey('slide_transition_duration_label'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
