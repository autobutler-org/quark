import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_chip.dart';
import 'package:quark_icons/quark_icons.dart';

/// One Upload chip, whatever this platform can upload.
///
/// Where more than one source exists the chip opens a chooser rather than
/// gaining a sibling in the toolbar, because no picker we can reach offers
/// those sources in one pass — `<input webkitdirectory>` selects folders
/// only, iOS's document picker is the Files app and cannot see the Camera
/// Roll, and file_picker implements a combined dialog on macOS alone. That
/// platform constraint belongs inside the Upload action, not spread across
/// the bar.
///
/// Photos is first when it is offered: backing up the Camera Roll is the
/// reason iOS users open `/files` (#1797).
///
/// While an upload runs the chip shows progress and stays live if there is a
/// way out: a batch failing its way through a large folder must not leave the
/// user watching a disabled button.
class FileTopBarUploadChip extends StatelessWidget {
  const FileTopBarUploadChip({
    required this.isUploading,
    required this.uploadTotal,
    required this.uploadCompleted,
    required this.onUploadPressed,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    super.key,
  });

  final bool isUploading;
  final int uploadTotal;
  final int uploadCompleted;
  final VoidCallback onUploadPressed;
  final VoidCallback? onUploadPhotosPressed;
  final VoidCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;

  @override
  Widget build(BuildContext context) {
    final label = isUploading
        ? (uploadTotal > 0 ? '$uploadCompleted/$uploadTotal' : 'Uploading...')
        : 'Upload';

    final onCancel = onCancelUploadPressed;
    final onUploadPhotos = onUploadPhotosPressed;
    final onUploadFolder = onUploadFolderPressed;

    final List<Widget>? menuItems;
    if (isUploading) {
      menuItems = onCancel == null
          ? null
          : [
              MenuItemButton(
                onPressed: onCancel,
                leadingIcon: const Icon(QuarkIcons.close_rounded),
                child: const Text('Cancel upload'),
              ),
            ];
    } else if (onUploadPhotos == null && onUploadFolder == null) {
      menuItems = null;
    } else {
      menuItems = [
        if (onUploadPhotos != null)
          MenuItemButton(
            onPressed: onUploadPhotos,
            leadingIcon: const Icon(QuarkIcons.photo_library_outlined),
            child: const Text('Photos'),
          ),
        MenuItemButton(
          onPressed: onUploadPressed,
          leadingIcon: const Icon(QuarkIcons.upload_rounded),
          child: const Text('Files'),
        ),
        if (onUploadFolder != null)
          MenuItemButton(
            onPressed: onUploadFolder,
            leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
            child: const Text('Folder'),
          ),
      ];
    }

    if (menuItems == null) {
      return TopBarChip(
        icon: QuarkIcons.upload_rounded,
        label: label,
        onTap: isUploading ? null : onUploadPressed,
      );
    }

    return MenuAnchor(
      menuChildren: menuItems,
      builder: (context, controller, _) {
        return TopBarChip(
          icon: QuarkIcons.upload_rounded,
          label: label,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }
}
