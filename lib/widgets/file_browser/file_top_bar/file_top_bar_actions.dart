import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_upload_chip.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The three things the wide layout lets the user add to the current folder.
///
/// With [canChooseDevice], Upload and New folder each get a second action
/// that asks which device to write to (#3194).
///
/// Probe keys: `file_top_bar_upload`, `file_top_bar_new_folder` and
/// `file_top_bar_new_file`, and `file_top_bar_upload_choose` and
/// `file_top_bar_new_folder_choose` on the choose-device segments.
class FileTopBarActions extends StatelessWidget {
  const FileTopBarActions({
    required this.isUploading,
    required this.uploadTotal,
    required this.uploadCompleted,
    required this.isCreatingFolder,
    required this.onUploadPressed,
    required this.onCreateFolderPressed,
    required this.onNewFilePressed,
    this.onUploadPhotosPressed,
    this.onUploadFolderPressed,
    this.onCancelUploadPressed,
    this.onShowUploadProgressPressed,
    this.canChooseDevice = false,
    super.key,
  });

  final bool isUploading;
  final int uploadTotal;
  final int uploadCompleted;
  final bool isCreatingFolder;
  final DeviceWriteCallback onUploadPressed;
  final DeviceWriteCallback onCreateFolderPressed;
  final VoidCallback onNewFilePressed;
  final DeviceWriteCallback? onUploadPhotosPressed;
  final DeviceWriteCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;
  final VoidCallback? onShowUploadProgressPressed;

  /// Whether there is more than one device to write to.
  final bool canChooseDevice;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FileTopBarUploadChip(
          isUploading: isUploading,
          uploadTotal: uploadTotal,
          uploadCompleted: uploadCompleted,
          onUploadPressed: onUploadPressed,
          onUploadPhotosPressed: onUploadPhotosPressed,
          onUploadFolderPressed: onUploadFolderPressed,
          onCancelUploadPressed: onCancelUploadPressed,
          onShowUploadProgressPressed: onShowUploadProgressPressed,
          canChooseDevice: canChooseDevice,
        ),
        const SizedBox(width: 6),
        QuarkBarSplitChip(
          key: const ValueKey('file_top_bar_new_folder'),
          icon: QuarkIcons.create_new_folder_outlined,
          label: 'New folder',
          onPressed: isCreatingFolder ? null : onCreateFolderPressed,
          onSecondaryPressed: canChooseDevice
              ? () => onCreateFolderPressed(chooseDevice: true)
              : null,
        ),
        const SizedBox(width: 6),
        QuarkBarChip(
          key: const ValueKey('file_top_bar_new_file'),
          icon: QuarkIcons.edit_document,
          label: 'New file',
          onPressed: onNewFilePressed,
        ),
      ],
    );
  }
}
