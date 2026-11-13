import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/move_rename_result.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/utils/trash_config.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/text_controller_scope.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The most bytes one file or folder name may take: the limit on ext4, APFS,
/// exFAT and every other filesystem a Quark stores to.
const int maxFileNameBytes = 255;

/// Why [name] cannot name a file or folder, or null when it can. Judged as it
/// will be sent — trimmed — so a name of only spaces is blank, and the length
/// is counted in UTF-8 bytes, which is what the filesystem limits.
String? fileNameProblem(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return Errors.nameBlank;
  if (utf8.encode(trimmed).length > maxFileNameBytes) {
    return Errors.nameTooLong;
  }
  return null;
}

Future<String?> promptForFolderName(BuildContext context) async {
  final value = await _promptForName(
    context,
    title: 'New Folder',
    label: 'Folder name',
    confirmLabel: 'Create',
    validator: fileNameProblem,
  );

  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }

  return normalized.replaceAll(RegExp(r'^/+|/+$'), '');
}

// startPath should be the current folder of the item being moved; returns a
// [MoveRenameResult] with the path and optional destination device serial.
// When [devices] has more than one entry a device picker dropdown is shown,
// starting on the device whose serial is [deviceSerial] — the one the item is
// on, empty for the internal drive.
Future<MoveRenameResult?> promptForMoveRenamePath(
  BuildContext context, {
  String startPath = '',
  String? initialName,
  List<StorageDevice> devices = const [],
  String deviceSerial = '',
  bool destinationOnly = false,
  Future<void> Function(String parentPath, String folderName, String? serial)?
  onCreateFolder,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return null;

  final controller = FileBrowserController();
  // Completed when the dialog closes, cancelling any listing still in flight
  // (#3995).
  final closed = Completer<void>();
  String currentAbsolutePath = normalizePath(
    startPath,
  ); // normalized with leading slash or empty
  if (currentAbsolutePath.startsWith('/')) {
    // normalizePath returns leading slash for non-empty; keep it
  } else {
    currentAbsolutePath = currentAbsolutePath; // keep empty
  }

  // Created on the first build for a path, not before the dialog is up.
  // Starting the request earlier lets it fail with nobody listening: widget
  // tests answer every HTTP call with 400, and that became an uncaught
  // exception (#2075). Replaced only when the folder changes, so typing in
  // the name does not start a new request and paint the previous rows.
  Future<List<FileNode>>? filesFuture;
  String? listedPath;
  StorageDevice? listedDevice;

  // Only show device picker when there are multiple devices
  final showDevicePicker = devices.length > 1;
  // Starts on the item's own device, so a plain rename stays put (#3193).
  StorageDevice? selectedDevice =
      devices.where((d) => d.serial == deviceSerial).firstOrNull ??
      devices.firstOrNull;

  // The folders on the destination, not every drive's merged (#3193). With no
  // picker there is no destination to choose and the listing is as it was.
  Future<List<FileNode>> filesOn(StorageDevice? device, String path) =>
      showDevicePicker && device != null
      ? controller.fetchDeviceFiles(
          path,
          device.serial,
          abortTrigger: closed.future,
        )
      : controller.fetchFiles(path, abortTrigger: closed.future);

  Future<List<FileNode>> listingFor(String path) {
    final current = filesFuture;
    if (listedPath != path ||
        listedDevice != selectedDevice ||
        current == null) {
      listedPath = path;
      listedDevice = selectedDevice;
      return filesFuture = filesOn(selectedDevice, path);
    }
    return current;
  }

  // Whether [device] has the folder [path]: it is listed in its parent there.
  Future<bool> hasFolder(StorageDevice device, String path) async {
    if (path.isEmpty) return true;
    try {
      final siblings = await filesOn(device, parentPath(path));
      return siblings.any((n) => n.isDir && normalizePath(n.apiPath) == path);
    } catch (_) {
      return false;
    }
  }

  final result = await QuarkWidget.showDialog<MoveRenameResult?>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => TextControllerScope(
      initialText: initialName?.trim().replaceAll('/', '') ?? '',
      builder: (_, nameController) {
        bool hasInvalidChar = nameController.text.contains('/');
        var creating = false;
        String? createError;
        return StatefulBuilder(
          builder: (context, setState) {
            void goTo(String path) {
              if (path == currentAbsolutePath) return;
              setState(() => currentAbsolutePath = path);
            }

            void openDirectory(FileNode node) {
              if (!node.isDir) return;
              final next = controller.nextPathForOpenDirectory(
                currentPath: currentAbsolutePath,
                node: node,
              );
              // Prevent opening the folder that's being moved into itself
              if (initialName != null && initialName.trim().isNotEmpty) {
                final targetOfNode = normalizePath(
                  joinPath(startPath, initialName),
                );
                if (next == targetOfNode) {
                  // Do nothing to prevent selecting the node itself as a destination
                  return;
                }
              }
              if (next == currentAbsolutePath) return;
              goTo(next);
            }

            void goUp() {
              goTo(parentPath(currentAbsolutePath));
            }

            String relativeToStart() {
              final normStart = normalizePath(startPath);
              final normCurrent = normalizePath(currentAbsolutePath);
              if (normStart.isEmpty) {
                // root start
                return normCurrent.startsWith('/')
                    ? normCurrent.substring(1)
                    : normCurrent;
              }
              if (normCurrent == normStart) return '';
              if (normCurrent.startsWith('$normStart/')) {
                return normCurrent.substring(normStart.length + 1);
              }
              // fallback to absolute with leading slash so callers treat it as absolute
              return normCurrent.startsWith('/')
                  ? normCurrent
                  : '/$normCurrent';
            }

            // Checked on every rebuild — the field's onChanged rebuilds — so
            // Save is only offered for a name the Quark can write. Saving a
            // blank or overlong name used to close the dialog and do nothing
            // (#2076).
            final nameProblem = hasInvalidChar
                ? null
                : fileNameProblem(nameController.text);

            return QuarkWidget.alertDialog(
              title: Text(destinationOnly ? 'Move' : 'Move / Rename'),
              scrollable: true,
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDevicePicker) ...[
                      DropdownButtonFormField<StorageDevice>(
                        initialValue: selectedDevice,
                        // A device name is arbitrary length and the dialog is
                        // narrow on a phone; without isExpanded the button sizes
                        // to the label and overflows its own row.
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Destination device',
                          isDense: true,
                        ),
                        items: devices
                            .map(
                              (d) => DropdownMenuItem<StorageDevice>(
                                value: d,
                                child: Text(
                                  d.name.isNotEmpty
                                      ? '${d.name}${d.isInternal ? ' (Internal)' : ''}'
                                      : d.mountPoint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          if (v == null || v == selectedDevice) return;
                          // The folder being browsed may not exist on the
                          // other drive; start from its root when it does not.
                          final path = await hasFolder(v, currentAbsolutePath)
                              ? currentAbsolutePath
                              : '';
                          if (!dialogContext.mounted) return;
                          setState(() {
                            selectedDevice = v;
                            currentAbsolutePath = path;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    FileBreadcrumbBar(
                      currentPath: currentAbsolutePath,
                      onGoHome: () => goTo(''),
                      onGoUp: goUp,
                      onPathSelected: goTo,
                      isSearchMode: false,
                    ),
                    SizedBox(
                      height: 300,
                      child: FileBrowserView(
                        key: ValueKey((
                          selectedDevice?.devicePath,
                          currentAbsolutePath,
                        )),
                        filesFuture: listingFor(currentAbsolutePath),
                        onFileMenuAction: (node, action) async {},
                        onOpenDirectory: openDirectory,
                        isGridView: false,
                        currentPath: currentAbsolutePath,
                        showFileSizeAndMenu: false,
                        errorBuilder: (context, error) => Center(
                          child: Text(
                            Errors.destinations(error),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (createError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          createError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    // Text field that prevents typing '/' and shows validation.
                    // A selection move has no name: each item keeps its own.
                    if (!destinationOnly)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          QuarkWidget.textField(
                            controller: nameController,
                            hintText: 'New file name',
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {},
                            onChanged: (v) {
                              setState(() {
                                hasInvalidChar = v.contains('/');
                              });
                            },
                            inputFormatters: [
                              FilteringTextInputFormatter.deny(RegExp(r'/')),
                            ],
                          ),
                          if (hasInvalidChar)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                'The file name cannot contain "/"',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (nameProblem != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                nameProblem,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                if (destinationOnly && onCreateFolder != null)
                  TextButton(
                    key: const ValueKey('move_destination_new_folder'),
                    onPressed: creating
                        ? null
                        : () async {
                            final name = await promptForFolderName(
                              dialogContext,
                            );
                            if (name == null || !dialogContext.mounted) return;
                            setState(() {
                              creating = true;
                              createError = null;
                            });
                            try {
                              await onCreateFolder(
                                currentAbsolutePath,
                                name,
                                selectedDevice?.serial,
                              );
                              if (!dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop(
                                MoveRenameResult(
                                  targetInput: joinPath(
                                    currentAbsolutePath,
                                    name,
                                  ),
                                  deviceSerial: selectedDevice?.serial,
                                ),
                              );
                            } catch (error) {
                              if (!dialogContext.mounted) return;
                              setState(() {
                                creating = false;
                                createError = Errors.upload(
                                  error,
                                  'create the folder',
                                );
                              });
                            }
                          },
                    child: const Text('New folder'),
                  ),
                TextButton(
                  onPressed: creating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                if (destinationOnly)
                  TextButton(
                    key: const ValueKey('move_destination_confirm'),
                    autofocus: true,
                    onPressed: creating
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop(
                              MoveRenameResult(
                                targetInput: currentAbsolutePath,
                                deviceSerial: selectedDevice?.serial,
                              ),
                            );
                          },
                    child: const Text('Move'),
                  )
                else
                  TextButton(
                    autofocus: true,
                    onPressed: hasInvalidChar || nameProblem != null
                        ? null
                        : () {
                            final name = nameController.text.trim();
                            final rel = relativeToStart();
                            String out;
                            if (rel.isEmpty) {
                              out = name;
                            } else {
                              out = '$rel/$name';
                            }
                            // The internal drive's serial is empty, and that
                            // is a choice: only "no device offered" is null.
                            Navigator.of(dialogContext).pop(
                              MoveRenameResult(
                                targetInput: out,
                                deviceSerial: selectedDevice?.serial,
                              ),
                            );
                          },
                    child: const Text('Save'),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
  closed.complete();

  if (result == null) return null;
  // The top of a device is a destination for a selection move. An empty name
  // on Move/Rename is still a cancel.
  if (destinationOnly) {
    return MoveRenameResult(
      targetInput: normalizePath(result.targetInput),
      deviceSerial: result.deviceSerial,
    );
  }
  final normalized = result.targetInput.trim();
  if (normalized.isEmpty) return null;
  // Collapse duplicate slashes and remove trailing slashes, preserving a single leading
  // slash for absolute targets (e.g. "/parent/file").
  final collapsed = normalized.replaceAll(RegExp(r'/+'), '/');
  final cleanPath = collapsed.replaceAll(RegExp(r'/+$'), '');
  return MoveRenameResult(
    targetInput: cleanPath,
    deviceSerial: result.deviceSerial,
  );
}

/// Shows [message] in a snack bar, with [action] and [duration] when given.
///
/// It queues behind a bar already on screen, which is Flutter's default, so
/// one message never cuts off another. A bar that replaces the last on purpose
/// (an undo) calls `hideCurrentSnackBar` itself. Does nothing once [context]
/// is unmounted or has no [ScaffoldMessenger] above it.
void showMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration ?? const Duration(milliseconds: 4000),
    ),
  );
}

/// Asks the user to confirm deleting [itemName]; true when they did. [count]
/// above one is a multi-select, and the title says how many: "Move 3 items to
/// Trash?".
///
/// Deleting moves the item to the trash rather than erasing it (#1844), so
/// this says so: a confirmation that reads like the last word before something
/// is gone forever is the wrong warning, and the one place a user decides is
/// here. The permanent step lives in the trash, behind its own confirmation.
Future<bool?> confirmDelete(
  BuildContext context,
  String itemName, {
  int count = 1,
}) {
  final one = count == 1;
  return confirmAction(
    context,
    title: one ? 'Move to Trash?' : 'Move $count items to Trash?',
    message:
        '$itemName ${one ? 'moves' : 'move'} to Trash. You can restore '
        '${one ? 'it' : 'them'} for ${TrashConfig.retentionDays} days.',
    confirmLabel: 'Move to Trash',
  );
}

/// Asks the user to confirm [confirmLabel] in a [ConfirmDeleteDialog]; true
/// when they did. [keyPrefix] keys the buttons `<keyPrefix>_cancel` and
/// `<keyPrefix>_confirm`, `confirm_action` when null. [destructive] draws the
/// confirm button in the error color.
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? keyPrefix,
  bool destructive = false,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return null;
  }

  return QuarkWidget.showDialog<bool>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => ConfirmDeleteDialog(
      title: title,
      body: message,
      keyPrefix: keyPrefix ?? 'confirm_action',
      confirmLabel: confirmLabel,
      destructive: destructive,
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
    ),
  );
}

/// [confirmAction] with a required [keyPrefix], destructive unless told
/// otherwise; true only when the user confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String keyPrefix,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async =>
    await confirmAction(
      context,
      title: title,
      message: body,
      keyPrefix: keyPrefix,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ) ==
    true;

/// Asks for one name in a [QuarkNameDialog] checked by [validator]; the
/// trimmed name, or null when canceled.
Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  required String? Function(String name) validator,
  String initialName = '',
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return null;
  }

  return QuarkWidget.showDialog<String>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => QuarkNameDialog(
      title: title,
      label: label,
      submitLabel: confirmLabel,
      initialName: initialName,
      validator: validator,
      onSubmit: (name) => Navigator.of(dialogContext).pop(name),
      onCancel: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

/// Prompts for the name of a new file (a doc, a sheet, …).
///
/// A `/` is rejected rather than treated as a directory. The upload endpoint
/// drops any directory in the multipart filename and writes the file at the
/// upload root under its basename, so a nested name would create the file
/// somewhere other than where the caller navigates — the #1603 404. Keeping
/// the name flat is what makes "the path we navigate to" and "the path the
/// backend wrote" the same string.
///
/// [initialName] prefills the field, for renaming.
///
/// Returns the trimmed name, or null when cancelled or left empty.
Future<String?> promptForNewFileName(
  BuildContext context, {
  required String title,
  required String hintText,
  String confirmLabel = 'Create',
  String initialName = '',
}) => _promptForName(
  context,
  title: title,
  label: hintText,
  confirmLabel: confirmLabel,
  initialName: initialName,
  validator: (name) =>
      name.contains('/') ? Errors.nameHasSlash : fileNameProblem(name),
);
