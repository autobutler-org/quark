import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A drive's health badge, the Quark's sentence, and the expandable readings.
///
/// Expansion stays here. The verdict and the readings come from [health].
class DriveHealthSection extends StatefulWidget {
  /// Creates the health block for [health], keyed with [id].
  const DriveHealthSection({required this.health, required this.id, super.key});

  /// The verdict, sentence, and readings to show.
  final DriveHealth health;

  /// Distinguishes this drive's keys from the others on the page.
  final String id;

  @override
  State<DriveHealthSection> createState() => _DriveHealthSectionState();
}

class _DriveHealthSectionState extends State<DriveHealthSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final verdict = widget.health.verdict;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QuarkTintBadge(
          key: ValueKey(
            widget.id.isEmpty
                ? 'drive_health_badge'
                : 'drive_health_badge_${widget.id}',
          ),
          label: verdict.label,
          color: driveHealthVerdictColor(QuarkTokens.of(context), verdict),
          semanticLabel: '${verdict.label} drive health',
        ),
        const SizedBox(height: 4),
        DriveHealthDetail(
          health: widget.health,
          id: widget.id,
          expanded: _expanded,
          onExpandedChanged: (open) => setState(() => _expanded = open),
        ),
      ],
    );
  }
}
