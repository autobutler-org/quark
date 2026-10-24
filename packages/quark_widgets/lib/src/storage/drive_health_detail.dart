// cspell:words reallocated
import 'package:flutter/material.dart';

import '../core/quark_detail_row.dart';
import '../theme/quark_tokens.dart';
import '../theme/reduce_motion.dart';
import 'drive_health.dart';

/// The sentence and the expandable readings for one drive's health.
///
/// [health] supplies the sentence and whichever readings the Quark sent.
/// A reading it did not send is left out. Power-on hours are shown as a
/// count of hours. Expansion is [expanded]; [onExpandedChanged] reports a
/// tap on Show details or Hide details.
///
/// Opening the readings animates unless reduced motion is on
/// (`MediaQuery.disableAnimations` or the platform reduce-motion flag), in
/// which case the rows appear at once.
///
/// Key prefixes: `drive_health_reason`, `drive_health_details`, and
/// `drive_health_row_<field>` for `smart`, `sectors`, `pending`, `hours`,
/// `temperature`, `media`, `link`, and `speed`. When [id] is set
/// it is inserted before the field: `drive_health_reason_<id>`,
/// `drive_health_details_<id>`, `drive_health_row_<id>_<field>`.
///
/// ```dart
/// DriveHealthDetail(
///   health: DriveHealth(
///     verdict: DriveHealthVerdict.watch,
///     reason: 'This spinning drive is heavily used.',
///     powerOnHours: 60000,
///   ),
///   expanded: false,
///   onExpandedChanged: (open) {},
/// )
/// ```
class DriveHealthDetail extends StatefulWidget {
  /// Creates the detail for [health].
  const DriveHealthDetail({
    required this.health,
    required this.expanded,
    required this.onExpandedChanged,
    this.id,
    super.key,
  });

  /// The verdict, sentence, and readings the Quark sent.
  final DriveHealth health;

  /// Whether the readings are open.
  final bool expanded;

  /// Called with the next open state when Show details or Hide details is tapped.
  final ValueChanged<bool> onExpandedChanged;

  /// Distinguishes keys when several drives share a tree. Null omits the id.
  final String? id;

  @override
  State<DriveHealthDetail> createState() => _DriveHealthDetailState();
}

class _DriveHealthDetailState extends State<DriveHealthDetail>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  String _key(String name) {
    final id = widget.id;
    if (id == null || id.isEmpty) return name;
    return '${name}_$id';
  }

  @override
  Widget build(BuildContext context) {
    final health = widget.health;
    final reason = health.reasonText;
    final rows = _rows(health);
    if (reason == null && rows.isEmpty) return const SizedBox.shrink();

    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final readings = widget.expanded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows)
        : const SizedBox(width: double.infinity, height: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reason != null)
          Text(
            reason,
            key: ValueKey(_key('drive_health_reason')),
            style: theme.textTheme.bodyMedium,
          ),
        if (rows.isNotEmpty)
          TextButton(
            key: ValueKey(_key('drive_health_details')),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.padded,
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => widget.onExpandedChanged(!widget.expanded),
            child: Text(widget.expanded ? 'Hide details' : 'Show details'),
          ),
        // AnimatedSize with a zero duration re-dirties itself during layout.
        if (reduceMotionOf(context))
          readings
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: readings,
          ),
      ],
    );
  }

  List<Widget> _rows(DriveHealth health) {
    final id = widget.id;
    String rowKey(String field) => id == null || id.isEmpty
        ? 'drive_health_row_$field'
        : 'drive_health_row_${id}_$field';

    final smart = health.smartStatusText;
    final hours = health.powerOnHoursText;
    final temperature = health.temperatureText;
    final media = health.mediaText;
    final link = health.linkSpeedText;
    final speed = health.speedClassText;
    final reallocated = health.reallocatedSectors;
    final pending = health.pendingSectors;

    return [
      if (smart != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('smart')),
          label: 'SMART status',
          value: smart,
        ),
      if (reallocated != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('sectors')),
          label: 'Reallocated sectors',
          value: '$reallocated',
        ),
      if (pending != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('pending')),
          label: 'Pending sectors',
          value: '$pending',
        ),
      if (hours != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('hours')),
          label: 'Power-on hours',
          value: hours,
        ),
      if (temperature != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('temperature')),
          label: 'Temperature',
          value: temperature,
        ),
      if (media != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('media')),
          label: 'Drive type',
          value: media,
        ),
      if (link != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('link')),
          label: 'Link speed',
          value: link,
        ),
      if (speed != null)
        QuarkDetailRow(
          key: ValueKey(rowKey('speed')),
          label: 'Speed class',
          value: speed,
        ),
    ];
  }
}
