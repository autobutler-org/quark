import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/move_rename_result.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/quark_widget.dart';
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
  final value = await _promptForText(
    context: context,
    title: 'New Folder',
    hintText: 'Folder name',
    confirmLabel: 'Create',
  );

  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }

  return normalized.replaceAll(RegExp(r'^/+|/+$'), '');
}

// startPath should be the current folder of the item being moved; returns a
// [MoveRenameResult] with the path and optional destination device serial.
// When [devices] has more than one entry a device picker dropdown is shown.
Future<MoveRenameResult?> promptForMoveRenamePath(
  BuildContext context, {
  String startPath = '',
  String? initialName,
  List<StorageDevice> devices = const [],
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return null;

  final controller = FileBrowserController();
  String currentAbsolutePath = normalizePath(
    startPath,
  ); // normalized with leading slash or empty
  if (currentAbsolutePath.startsWith('/')) {
    // normalizePath returns leading slash for non-empty; keep it
  } else {
    currentAbsolutePath = currentAbsolutePath; // keep empty
  }

  // Only show device picker when there are multiple devices
  final showDevicePicker = devices.length > 1;
  StorageDevice? selectedDevice = devices.isNotEmpty ? devices.first : null;

  final result = await QuarkWidget.showDialog<MoveRenameResult?>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => TextControllerScope(
      initialText: initialName?.trim().replaceAll('/', '') ?? '',
      builder: (_, nameController) {
        bool hasInvalidChar = nameController.text.contains('/');
        return StatefulBuilder(
          builder: (context, setState) {
            Future<List<FileNode>> filesFuture() {
              return controller.fetchFiles(currentAbsolutePath);
            }

            void openDirectory(FileNode node) {
              if (!node.isDir) return;
              // Prevent opening the folder that's being moved into itself
              if (initialName != null && initialName.trim().isNotEmpty) {
                final targetOfNode = normalizePath(
                  joinPath(startPath, initialName),
                );
                final candidate = normalizePath(
                  joinPath(currentAbsolutePath, node.name),
                );
                if (candidate == targetOfNode) {
                  // Do nothing to prevent selecting the node itself as a destination
                  return;
                }
              }
              setState(() {
                currentAbsolutePath = joinPath(currentAbsolutePath, node.name);
              });
            }

            void goUp() {
              setState(() {
                currentAbsolutePath = parentPath(currentAbsolutePath);
              });
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
              title: const Text('Move / Rename'),
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
                        onChanged: (v) {
                          if (v != null) setState(() => selectedDevice = v);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    FileBreadcrumbBar(
                      currentPath: currentAbsolutePath,
                      onGoHome: () {
                        setState(() {
                          currentAbsolutePath = '';
                        });
                      },
                      onGoUp: goUp,
                      onPathSelected: (path) {
                        setState(() {
                          currentAbsolutePath = path;
                        });
                      },
                      isSearchMode: false,
                    ),
                    SizedBox(
                      height: 300,
                      child: FileBrowserView(
                        filesFuture: filesFuture(),
                        onFileMenuAction: (node, action) async {},
                        onOpenDirectory: openDirectory,
                        isGridView: false,
                        currentPath: currentAbsolutePath,
                        showFileSizeAndMenu: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Text field that prevents typing '/' and shows validation
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
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
                          final serial = selectedDevice?.serial;
                          Navigator.of(dialogContext).pop(
                            MoveRenameResult(
                              targetInput: out,
                              deviceSerial:
                                  (serial != null && serial.isNotEmpty)
                                  ? serial
                                  : null,
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

  if (result == null) return null;
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

Future<bool?> confirmDelete(BuildContext context, String itemName) =>
    confirmAction(
      context,
      title: 'Delete',
      message: 'Delete $itemName?',
      confirmLabel: 'Delete',
    );

/// Asks the user to confirm [confirmLabel]; true when they did.
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return null;
  }

  return QuarkWidget.showDialog<bool>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) {
      return QuarkWidget.alertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

Future<String?> _promptForText({
  required BuildContext context,
  required String title,
  required String hintText,
  required String confirmLabel,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return null;
  }

  final String? value = await QuarkWidget.showDialog(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => TextControllerScope(
      builder: (_, textController) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: textController,
        builder: (context, text, _) {
          // An empty field is where every new name starts, so a blank name
          // only disables the button; any other problem says why. A blank
          // name used to close the dialog with nothing created (#2074).
          final problem = fileNameProblem(text.text);
          void submit() {
            if (fileNameProblem(textController.text) == null) {
              Navigator.of(dialogContext).pop(textController.text.trim());
            }
          }

          return QuarkWidget.alertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QuarkWidget.textField(
                    controller: textController,
                    autofocus: true,
                    hintText: hintText,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                  ),
                  if (problem != null && problem != Errors.nameBlank)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        problem,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                autofocus: true,
                onPressed: problem == null ? submit : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    ),
  );

  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
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
/// Returns the trimmed name, or null when cancelled or left empty.
Future<String?> promptForNewFileName(
  BuildContext context, {
  required String title,
  required String hintText,
  String confirmLabel = 'Create',
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return null;
  }

  final String? value = await QuarkWidget.showDialog<String>(
    context,
    useRootNavigator: true,
    builder: (dialogContext) => TextControllerScope(
      builder: (_, nameController) {
        bool hasInvalidChar = false;
        return StatefulBuilder(
          builder: (context, setState) {
            // As for a new folder: blank only disables Create.
            final problem = fileNameProblem(nameController.text);
            void submit() {
              final name = nameController.text.trim();
              if (fileNameProblem(name) != null || name.contains('/')) return;
              Navigator.of(dialogContext).pop(name);
            }

            return QuarkWidget.alertDialog(
              title: Text(title),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QuarkWidget.textField(
                      controller: nameController,
                      autofocus: true,
                      hintText: hintText,
                      textInputAction: TextInputAction.done,
                      onChanged: (v) => setState(() {
                        hasInvalidChar = v.contains('/');
                      }),
                      onSubmitted: (_) => submit(),
                    ),
                    if (hasInvalidChar)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          'The name cannot contain "/"',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else if (problem != null && problem != Errors.nameBlank)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          problem,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  autofocus: true,
                  onPressed: hasInvalidChar || problem != null ? null : submit,
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    ),
  );

  final normalized = (value ?? '').trim();
  if (normalized.isEmpty || normalized.contains('/')) {
    return null;
  }
  return normalized;
}
