import 'package:flutter/material.dart';
import 'package:quark/widgets/health/health_severity.dart';
import 'package:quark_icons/quark_icons.dart';

/// Summary banner at the top of the health page, listing any alerts.
///
/// [severity] is the worst reading, not only whether the Quark raised a
/// critical alert. Calm stays "All systems healthy", an orange meter or core
/// says "Some readings are elevated", and a red reading or a backend alert
/// says "Issues detected".
class StatusBanner extends StatelessWidget {
  const StatusBanner({required this.severity, required this.alerts, super.key});

  final HealthSeverity severity;
  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    final Color onColor;
    final IconData icon;
    final String label;
    switch (severity) {
      case HealthSeverity.healthy:
        color = scheme.primaryContainer;
        onColor = scheme.onPrimaryContainer;
        icon = QuarkIcons.check_circle_outline;
        label = 'All systems healthy';
      case HealthSeverity.warning:
        color = Colors.orange.shade100;
        onColor = Colors.orange.shade900;
        icon = QuarkIcons.warning_amber;
        label = 'Some readings are elevated';
      case HealthSeverity.critical:
        color = scheme.errorContainer;
        onColor = scheme.onErrorContainer;
        icon = QuarkIcons.warning_amber;
        label = 'Issues detected';
    }

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: onColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...alerts.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• $a',
                    style: TextStyle(color: onColor, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
