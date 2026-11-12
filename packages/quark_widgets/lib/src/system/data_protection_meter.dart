import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';
import '../theme/reduce_motion.dart';
import 'data_protection_level.dart';

/// Three steps — Unprotected, Basic, Protected — filled through [level].
///
/// The fill runs once, left to right, and stops on the step [level] names.
/// Under reduced motion (`MediaQuery.disableAnimationsOf`, or the platform
/// `accessibilityFeatures.reduceMotion` flag) the fill is already on that
/// step. The caller passes [level]. The meter does not count drives.
///
/// Key prefixes: `data_protection_meter_step_<level>` and
/// `data_protection_meter_label_<level>` on each step. Pass [id] when more
/// than one meter is on screen; the keys become
/// `data_protection_meter_<id>_step_<level>` and
/// `data_protection_meter_<id>_label_<level>`.
///
/// ```dart
/// DataProtectionMeter(level: DataProtectionLevel.basic)
/// ```
class DataProtectionMeter extends StatefulWidget {
  /// Creates a meter filled through [level].
  const DataProtectionMeter({required this.level, this.id, super.key});

  /// The step the fill stops on.
  final DataProtectionLevel level;

  /// Distinguishes this meter's keys when another meter is in the same tree.
  /// Null uses the prefixes with no extra segment.
  final String? id;

  @override
  State<DataProtectionMeter> createState() => _DataProtectionMeterState();
}

class _DataProtectionMeterState extends State<DataProtectionMeter>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _fill = Duration(milliseconds: 400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _fill,
  );
  bool _played = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyMotion();
  }

  @override
  void didUpdateWidget(DataProtectionMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) _applyMotion(replay: true);
  }

  @override
  void didChangeAccessibilityFeatures() => _applyMotion();

  /// Jumps to the end when reduced motion is on. Otherwise plays the fill
  /// once, or again when [replay] is set.
  void _applyMotion({bool replay = false}) {
    final reduce = reduceMotionOf(context);
    if (reduce) {
      _played = true;
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 1) _controller.value = 1;
      return;
    }
    if (replay || !_played) {
      _played = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  String _key(String part) {
    final id = widget.id;
    final prefix = id == null
        ? 'data_protection_meter_'
        : 'data_protection_meter_${id}_';
    return '$prefix$part';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final status = dataProtectionLevelColor(tokens, widget.level);
    final reached = widget.level.index + 1;

    return Semantics(
      container: true,
      label: '${widget.level.label} protection',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final eased = Curves.easeOut.transform(_controller.value);
          final shown = eased * reached;
          return ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < DataProtectionLevel.values.length; i++) ...[
                  if (i > 0) SizedBox(width: tokens.spacingSm),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          DataProtectionLevel.values[i].label,
                          key: ValueKey(
                            _key('label_${DataProtectionLevel.values[i].name}'),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: i <= widget.level.index
                                ? tokens.cardForeground
                                : tokens.mutedForeground,
                            fontWeight: i == widget.level.index
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: tokens.spacingXs),
                        DecoratedBox(
                          key: ValueKey(
                            _key('step_${DataProtectionLevel.values[i].name}'),
                          ),
                          decoration: BoxDecoration(
                            color: _segmentColor(
                              tokens,
                              status,
                              (shown - i).clamp(0.0, 1.0),
                            ),
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                          child: const SizedBox(
                            height: 8,
                            width: double.infinity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Color _segmentColor(QuarkTokens tokens, Color status, double fill) {
    if (fill <= 0) return tokens.sidebar;
    if (fill >= 1) return status;
    return Color.lerp(tokens.sidebar, status, fill)!;
  }
}
