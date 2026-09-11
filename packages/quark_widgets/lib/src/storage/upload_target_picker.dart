import 'package:flutter/material.dart';

import '../models/upload_target.dart';
import '../theme/quark_tokens.dart';

/// The body of a bottom sheet for choosing which device an upload goes to.
///
/// A radio list of [targets] with cancel and upload buttons. The choice is the
/// caller's: [selected] in, [onSelected] out, and [onConfirm] fires when the
/// user commits to it.
///
/// Key prefixes: `upload_target_<index>` on each radio row (by position, since
/// a default device may have no serial), `upload_target_cancel` and
/// `upload_target_confirm` on the buttons.
///
/// ```dart
/// UploadTargetPicker(
///   targets: targets,
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

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
              child: Text(
                'Upload to device',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(height: tokens.spacingSm),
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
                      title: Text(
                        target.name.isNotEmpty ? target.name : 'Device',
                      ),
                      subtitle: Text(
                        [
                          if (target.mountPoint.isNotEmpty) target.mountPoint,
                          if (target.isInternal) 'Internal',
                        ].join(' · '),
                      ),
                      value: target,
                    ),
                ],
              ),
            ),
            SizedBox(height: tokens.spacingSm),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }
}
