import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/quark_folder_entry.dart';
import '../theme/quark_tokens.dart';

/// A drill-down list of folders for choosing a destination, such as where a
/// chat attachment is saved.
///
/// The caller owns the data. [folders] is whatever the folder on screen
/// contains, [currentPath] and [currentName] name that folder, and
/// [canGoUp] says whether it has a parent. Tapping a row calls [onOpen] so
/// the caller can list that folder. The up control calls [onUp]. "Save here"
/// calls [onSelect] for the folder on screen, and stays available when that
/// folder is empty.
///
/// It never fetches. [isLoading] with no [folders] and no [error] draws a
/// [QuarkLoader]. [error] is shown as the caller wrote it, in place of the
/// rows and the loader. A refresh that already has rows keeps them.
///
/// Give it a bounded height (a page body, a dialog, a [SizedBox]) and the
/// list scrolls under a pinned "Save here". In a parent that scrolls, the
/// picker shrinks to its rows instead, so it never puts an [Expanded] in an
/// unbounded height.
///
/// Key prefixes: `folder_picker_up` on the up control, shown only when
/// [canGoUp] is true; `folder_picker_select` on "Save here"; and
/// `folder_picker_row_<path>` on each row, with every `/` in the path
/// replaced by `_`.
///
/// ```dart
/// QuarkFolderPicker(
///   folders: const [
///     QuarkFolderEntry(path: '/Documents', name: 'Documents'),
///     QuarkFolderEntry(path: '/Photos', name: 'Photos'),
///   ],
///   currentPath: '/',
///   currentName: 'My files',
///   canGoUp: false,
///   onOpen: (folder) => openFolder(folder),
///   onSelect: saveHere,
/// )
/// ```
class QuarkFolderPicker extends StatelessWidget {
  /// Creates a picker for the folder at [currentPath].
  const QuarkFolderPicker({
    required this.folders,
    required this.currentPath,
    required this.currentName,
    required this.canGoUp,
    required this.onOpen,
    required this.onSelect,
    this.isLoading = false,
    this.error,
    this.onUp,
    super.key,
  });

  /// The folders inside [currentPath], in the order they are shown.
  final List<QuarkFolderEntry> folders;

  /// The Quark files path of the folder being shown. `/` is the root.
  final String currentPath;

  /// The title of the folder being shown. The root's name is whatever the
  /// caller passes, for example "My files".
  final String currentName;

  /// Whether the up control is shown. False at the root, where there is no
  /// parent to open.
  final bool canGoUp;

  /// Whether the listing is still loading. With no [folders] and no [error],
  /// draws a [QuarkLoader] instead of the empty message.
  final bool isLoading;

  /// A message the caller wrote for a listing that failed, or null. Rendered
  /// as given, in place of the rows and the loader. The picker does not
  /// compose a sentence of its own.
  final String? error;

  /// Called with the folder whose row was tapped, so the caller can list it.
  final ValueChanged<QuarkFolderEntry> onOpen;

  /// Called when the up control is tapped. Null leaves that control
  /// disabled. The control is absent when [canGoUp] is false.
  final VoidCallback? onUp;

  /// Called when "Save here" is tapped, choosing the folder on screen as the
  /// destination. Stays available while the folder is empty, loading, or
  /// failed, because the destination is [currentPath], not a child row.
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final titleStyle = (theme.textTheme.titleMedium ?? const TextStyle())
        .copyWith(color: tokens.foreground, fontWeight: FontWeight.w600);
    final pathStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: tokens.mutedForeground,
    );
    final messageStyle = theme.textTheme.bodyMedium ?? const TextStyle();
    final error = this.error;

    return LayoutBuilder(
      builder: (_, constraints) {
        // A scroll view hands this an unbounded height, where Expanded
        // throws (#1599). There the list shrinks and the parent scrolls. A
        // bounded parent pins "Save here" and scrolls the list.
        final bounded = constraints.maxHeight.isFinite;
        final Widget body;
        if (error != null) {
          body = Center(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacingLg),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: messageStyle.copyWith(color: tokens.error),
                ),
              ),
            ),
          );
        } else if (isLoading && folders.isEmpty) {
          body = const Center(child: QuarkLoader());
        } else if (folders.isEmpty) {
          body = Center(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacingLg),
              child: Text(
                'This folder is empty',
                textAlign: TextAlign.center,
                style: messageStyle.copyWith(color: tokens.mutedForeground),
              ),
            ),
          );
        } else {
          body = ListView.builder(
            shrinkWrap: !bounded,
            physics: bounded ? null : const NeverScrollableScrollPhysics(),
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                key: ValueKey(
                  'folder_picker_row_${folder.path.replaceAll('/', '_')}',
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: tokens.spacingMd,
                ),
                leading: Icon(
                  QuarkIcons.folder,
                  color: tokens.secondaryForeground,
                ),
                title: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpen(folder),
              );
            },
          );
        }

        return Column(
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                canGoUp ? tokens.spacingXs : tokens.spacingMd,
                tokens.spacingXs,
                tokens.spacingMd,
                tokens.spacingXs,
              ),
              child: Row(
                children: [
                  if (canGoUp)
                    Tooltip(
                      message: 'Up one level',
                      child: TextButton.icon(
                        key: const ValueKey('folder_picker_up'),
                        onPressed: onUp,
                        icon: const Icon(
                          QuarkIcons.arrow_upward_rounded,
                          size: 18,
                        ),
                        label: const Text('Up'),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        Text(
                          currentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: pathStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.border),
            if (bounded) Expanded(child: body) else body,
            Divider(height: 1, thickness: 1, color: tokens.border),
            Padding(
              padding: EdgeInsets.all(tokens.spacingMd),
              child: FilledButton(
                key: const ValueKey('folder_picker_select'),
                onPressed: onSelect,
                child: const Text('Save here'),
              ),
            ),
          ],
        );
      },
    );
  }
}
