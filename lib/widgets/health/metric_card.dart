import 'package:flutter/material.dart';

/// One health metric: a labelled value with a progress bar that turns orange
/// then red as it approaches [criticalThreshold].
///
/// The orange band starts well below the threshold the Quark alerts on —
/// three quarters of it — so a meter can look like a warning while the page's
/// banner truthfully says nothing is wrong. That contradiction is the whole
/// of #2048, and the band now says what it means: elevated, with the number
/// that would actually raise an alert.
///
/// Key prefixes: `metric_note_<label>`, lowercased, on the note under the bar.
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.criticalThreshold,
    this.maxValue = 100,
    this.detail,
    this.corePercents,
    super.key,
  });

  final String label;
  final IconData icon;
  final double value;
  final String unit;
  final double criticalThreshold;
  final double maxValue;
  final String? detail;
  final List<double>? corePercents;

  /// Where the bar stops being calm. Three quarters of the alert threshold.
  double get _elevatedFrom => criticalThreshold * 0.75;

  /// Whether the value is in the orange band: past calm, short of an alert.
  bool get _isElevated => value >= _elevatedFrom && value < criticalThreshold;

  /// Whether the Quark would be raising an alert for this value.
  bool get _isCritical => value >= criticalThreshold;

  Color _barColor(BuildContext context) {
    if (_isCritical) return Theme.of(context).colorScheme.error;
    if (_isElevated) return Colors.orange;
    return Theme.of(context).colorScheme.primary;
  }

  /// What the color means, or null while the bar is calm and means nothing
  /// worth a line of text.
  String? get _note {
    final limit = criticalThreshold.toStringAsFixed(0);
    if (_isCritical) {
      return 'Over the $limit$unit limit — this raises an alert.';
    }
    if (_isElevated) {
      return 'Elevated, and normal. Nothing is wrong until $limit$unit.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (value / maxValue).clamp(0.0, 1.0);
    final barColor = _barColor(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${value.toStringAsFixed(1)}$unit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: barColor,
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                color: barColor,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                minHeight: 8,
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: 6),
              Text(
                key: ValueKey('metric_note_${label.toLowerCase()}'),
                _note!,
                style: TextStyle(
                  fontSize: 12,
                  color: _isCritical
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (corePercents != null && corePercents!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: () {
                  final total = corePercents!.fold(0.0, (s, v) => s + v);
                  return corePercents!.asMap().entries.map((e) {
                    final contribution = total > 0
                        ? (e.value / total * 100)
                        : 0.0;
                    final coreColor = e.value >= 90
                        ? Theme.of(context).colorScheme.error
                        : e.value >= 67
                        ? Colors.orange
                        : Theme.of(context).colorScheme.primary;
                    return Chip(
                      label: Text(
                        'Core ${e.key + 1}: ${e.value.toStringAsFixed(0)}% (${contribution.toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 11, color: coreColor),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: coreColor.withValues(alpha: 0.4)),
                      backgroundColor: coreColor.withValues(alpha: 0.08),
                    );
                  }).toList();
                }(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
