import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';

/// Confirms ejecting the drive named [driveName]. Pops with `true` on Eject,
/// or with nothing on Cancel. Warns when the drive is default storage, since
/// new uploads have nowhere to go until it is mounted again.
class EjectDriveDialog extends StatelessWidget {
  const EjectDriveDialog({
    required this.driveName,
    required this.isDefaultStorage,
    super.key,
  });

  /// The drive's name; empty reads as "this drive".
  final String driveName;

  /// Whether the drive holds the default-storage role.
  final bool isDefaultStorage;

  @override
  Widget build(BuildContext context) {
    final name = driveName.isNotEmpty ? driveName : 'this drive';
    return QuarkWidget.alertDialog(
      title: const Text('Eject drive?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quark stops using $name so you can unplug it safely. Its files '
            'will not appear in Files until it is mounted again.',
          ),
          if (isDefaultStorage) ...[
            const SizedBox(height: 16),
            Text(
              key: const ValueKey('eject_dialog_default_storage_warning'),
              'This is the default storage drive. New uploads will fail '
              'until it is mounted again.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('eject_dialog_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('eject_dialog_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eject'),
        ),
      ],
    );
  }
}
