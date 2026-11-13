import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// An action that writes to a storage device: an upload or a new folder. A
/// plain call goes to the default storage device; [chooseDevice] opens the
/// device sheet first, so the user can pick another (#3194).
typedef DeviceWriteCallback = void Function({bool chooseDevice});

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
///
/// While an upload runs its menu also offers Show progress, which opens the
/// Jobs tab with each file's bytes, rate and time left (#3972).
///
/// With [canChooseDevice] the chip is a [QuarkBarSplitChip]: the chip uploads
/// to the default storage device and its ▾ segment to a device the user
/// picks (#3194). Where the chip opens the source chooser, the ▾ segment
/// opens the same chooser, and the source picked there asks for the device.
///
/// Probe keys: `file_top_bar_upload`, `file_top_bar_upload_choose`,
/// `file_top_bar_upload_progress`.
class FileTopBarUploadChip extends StatelessWidget {
  const FileTopBarUploadChip({
    required this.isUploading,
    required this.uploadTotal,
    required this.uploadCompleted,
    required this.onUploadPressed,
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
  final DeviceWriteCallback onUploadPressed;
  final DeviceWriteCallback? onUploadPhotosPressed;
  final DeviceWriteCallback? onUploadFolderPressed;
  final VoidCallback? onCancelUploadPressed;

  /// Opens where each file's progress is shown, the Jobs tab (#3972).
  final VoidCallback? onShowUploadProgressPressed;

  /// Whether there is more than one device to upload to, which adds the ▾
  /// segment.
  final bool canChooseDevice;

  @override
  Widget build(BuildContext context) {
    final label = isUploading
        ? (uploadTotal > 0 ? '$uploadCompleted/$uploadTotal' : 'Uploading...')
        : 'Upload';

    final onCancel = onCancelUploadPressed;
    final onShowProgress = onShowUploadProgressPressed;
    final onUploadPhotos = onUploadPhotosPressed;
    final onUploadFolder = onUploadFolderPressed;

    void toggle(MenuController menu) =>
        menu.isOpen ? menu.close() : menu.open();

    if (isUploading) {
      final menuItems = [
        if (onShowProgress != null)
          MenuItemButton(
            key: const ValueKey('file_top_bar_upload_progress'),
            onPressed: onShowProgress,
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.pending_actions_outlined),
              label: const Text('Show progress'),
            ),
          ),
        if (onCancel != null)
          MenuItemButton(
            onPressed: onCancel,
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.close),
              label: const Text('Cancel upload'),
            ),
          ),
      ];
      return MenuAnchor(
        menuChildren: menuItems,
        builder: (context, menu, _) => QuarkBarChip(
          key: const ValueKey('file_top_bar_upload'),
          icon: QuarkIcons.upload_rounded,
          label: label,
          onPressed: menuItems.isEmpty ? null : () => toggle(menu),
        ),
      );
    }

    if (onUploadPhotos == null && onUploadFolder == null) {
      return QuarkBarSplitChip(
        key: const ValueKey('file_top_bar_upload'),
        icon: QuarkIcons.upload_rounded,
        label: label,
        onPressed: onUploadPressed,
        onSecondaryPressed: canChooseDevice
            ? () => onUploadPressed(chooseDevice: true)
            : null,
      );
    }

    List<Widget> sources({required bool chooseDevice}) => [
      if (onUploadPhotos != null)
        MenuItemButton(
          onPressed: () => onUploadPhotos(chooseDevice: chooseDevice),
          child: quarkMenuLabel(
            leading: const Icon(QuarkIcons.photo_library),
            label: const Text('Photos'),
          ),
        ),
      MenuItemButton(
        onPressed: () => onUploadPressed(chooseDevice: chooseDevice),
        child: quarkMenuLabel(
          leading: const Icon(QuarkIcons.upload_rounded),
          label: const Text('Files'),
        ),
      ),
      if (onUploadFolder != null)
        MenuItemButton(
          onPressed: () => onUploadFolder(chooseDevice: chooseDevice),
          child: quarkMenuLabel(
            leading: const Icon(QuarkIcons.drive_folder_upload_outlined),
            label: const Text('Folder'),
          ),
        ),
    ];

    // Two menus on one chip: the plain one uploads to the default device,
    // the ▾ one asks which device once the source has been picked.
    return MenuAnchor(
      menuChildren: sources(chooseDevice: false),
      builder: (context, plain, _) => MenuAnchor(
        menuChildren: sources(chooseDevice: true),
        builder: (context, choosing, _) => QuarkBarSplitChip(
          key: const ValueKey('file_top_bar_upload'),
          icon: QuarkIcons.upload_rounded,
          label: label,
          onPressed: () => toggle(plain),
          onSecondaryPressed: canChooseDevice ? () => toggle(choosing) : null,
        ),
      ),
    );
  }
}
