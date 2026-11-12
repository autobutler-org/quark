import 'package:material_ui/material_ui.dart';

import '../layout/quark_sheet.dart';
import '../models/upload_target.dart';
import '../theme/quark_tokens.dart';

/// The body of a bottom sheet for choosing which device an upload goes to.
/// Show it with [showQuarkSheet], which gives it its title, close button and
/// height cap (#2585).
///
/// A radio list of [targets] with cancel and upload buttons. The choice is the
/// caller's: [selected] in, [onSelected] out, and [onConfirm] fires when the
/// user commits to it. A target with an [UploadTarget.unavailableReason] is
/// listed with that reason under its name and cannot be chosen (#3191). The
/// one with [UploadTarget.isDefault] set reads "Default" under its name, which
/// is why the caller started on it (#3194). A [notice] reads above the list,
/// for what the caller has to say about the choice, such as there being no
/// default device to upload to without asking.
///
/// Key prefixes: `upload_target_<index>` on each radio row (by position, since
/// a default device may have no serial), `upload_target_cancel` and
/// `upload_target_confirm` on the buttons, `upload_target_notice` on the
/// notice.
///
/// ```dart
/// UploadTargetPicker(
///   targets: targets,
///   notice: 'No default storage device is connected.',
///   selected: chosen,
///   onSelected: (target) => setState(() => chosen = target),
///   onCancel: () => Navigator.of(context).pop(),
///   onConfirm: () => Navigator.of(context).pop(chosen),
/// );
/// ```
class UploadTargetPicker extends StatelessWidget {
  /// Creates the picker over [targets].
  const UploadTargetPicker({
    required this.targets,
    required this.selected,
    required this.onSelected,
    required this.onCancel,
    required this.onConfirm,
    this.notice,
    super.key,
  });

  /// The devices to choose between.
  final List<UploadTarget> targets;

  /// The device currently chosen, or null for none.
  final UploadTarget? selected;

  /// Called with the device whose row was tapped.
  final ValueChanged<UploadTarget> onSelected;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// Called when the upload button is tapped.
  final VoidCallback onConfirm;

  /// A line above the list about the choice; null shows none.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final notice = this.notice;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          Text(
            notice,
            key: const ValueKey('upload_target_notice'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.mutedForeground),
          ),
          SizedBox(height: tokens.spacingSm),
        ],
        RadioGroup<UploadTarget>(
          groupValue: selected,
          onChanged: (target) {
            if (target != null) onSelected(target);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, target) in targets.indexed)
                RadioListTile<UploadTarget>(
                  key: ValueKey('upload_target_$index'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(target.name.isNotEmpty ? target.name : 'Device'),
                  subtitle: Text(
                    [
                      if (target.mountPoint.isNotEmpty) target.mountPoint,
                      if (target.isInternal) 'Internal',
                      if (target.isDefault) 'Default',
                      ?target.unavailableReason,
                    ].join(' · '),
                  ),
                  value: target,
                  enabled: target.unavailableReason == null,
                ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacingSm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const ValueKey('upload_target_cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
            SizedBox(width: tokens.spacingSm),
            FilledButton(
              key: const ValueKey('upload_target_confirm'),
              onPressed: onConfirm,
              child: const Text('Upload'),
            ),
          ],
        ),
      ],
    );
  }
}
