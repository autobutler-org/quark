import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_upload_chip.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The three things the wide layout lets the user add to the current folder.
///
/// Probe keys: `file_top_bar_upload`, `file_top_bar_new_folder` and
/// `file_top_bar_new_file`.
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
    super.key,
  });

  final bool isUploading;
  final int uploadTotal;
  final int uploadCompleted;
  final bool isCreatingFolder;
  final VoidCallback onUploadPressed;
  final VoidCallback onCreateFolderPressed;
  final VoidCallback onNewFilePressed;
  final VoidCallback? onUploadPhotosPressed;
  final VoidCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;

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
        ),
        const SizedBox(width: 6),
        QuarkBarChip(
          key: const ValueKey('file_top_bar_new_folder'),
          icon: QuarkIcons.create_new_folder_outlined,
          label: 'New folder',
          onPressed: isCreatingFolder ? null : onCreateFolderPressed,
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
