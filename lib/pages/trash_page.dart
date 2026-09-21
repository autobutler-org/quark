import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/trash_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_device_chips.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Deleted files, listed in the Files viewer with only Restore and Delete
/// permanently on offer. Folders open, so a trashed folder can be browsed and
/// picked through; files do not: a trashed file is a thing to put back or let
/// go, not to read.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, this.location});

  /// The folder to browse, from the route; null is the trash root.
  final TrashLocation? location;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  static const _trashActions = {
    FileMenuAction.restore,
    FileMenuAction.deletePermanently,
  };

  late final _controller = TrashController(location: widget.location);
  StreamSubscription<FileEvent>? _eventSub;
  StreamSubscription<void>? _reconnectSub;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_followController);
    EventsService.instance.start();
    // Every trash mutation, from any client, and the hourly purge; and a
    // sharing change, which decides which trashed items this account sees.
    _eventSub = EventsService.instance.events.listen((evt) {
      if (evt.kind == 'trash_changed' || evt.kind == 'access_changed') {
        manualRefresh();
      }
    });
    // Whatever changed while the socket was down sent no event we saw.
    _reconnectSub = EventsService.instance.reconnects.listen(
      (_) => manualRefresh(),
    );
  }

  @override
  void didUpdateWidget(covariant TrashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location) {
      unawaited(_controller.open(widget.location));
    }
  }

  /// Puts the URL where the controller is when a load climbed out of a folder
  /// that disappeared, so back and reload do not return to it.
  void _followController() {
    if (mounted && _controller.location != widget.location) {
      context.go(AppRoutes.trashFolder(_controller.location));
    }
  }

  void _go(TrashLocation? location) =>
      context.go(AppRoutes.trashFolder(location));

  void _openFolder(FileNode node) {
    if (!node.isDir) return;
    final ref = TrashController.refFor(node);
    _go((serial: node.deviceSerial, trashName: ref.trashName, path: ref.path));
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _reconnectSub?.cancel();
    _controller
      ..removeListener(_followController)
      ..dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.load();

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  static String _items(int count) => count == 1 ? '1 item' : '$count items';

  Future<void> _onMenuAction(FileNode node, FileMenuAction action) async {
    switch (action) {
      case FileMenuAction.restore:
        await _restore([node]);
      case FileMenuAction.deletePermanently:
        await _deletePermanently([node]);
      default:
        break;
    }
  }

  Future<void> _restore(List<FileNode> nodes) async {
    if (nodes.isEmpty) return;
    try {
      final count = await _controller.restore(nodes);
      if (mounted) _showMessage('Restored ${_items(count)}');
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        Errors.restore(
          e,
          nodes.length == 1 ? 'restore the item' : 'restore the items',
        ),
        // A 409 means something is already where this item goes back to.
        // Telling the user to move or rename it, without saying where it is,
        // leaves them to search for it (#2014). The Quark never overwrites,
        // so opening the folder is the action that actually unblocks them.
        action: _conflictAction(e, nodes),
      );
    }
    unawaited(manualRefresh());
  }

  /// Takes the user to the folder a refused restore collided with, when the
  /// Quark said the destination was occupied and still knows where that is.
  SnackBarAction? _conflictAction(Object error, List<FileNode> nodes) {
    if (error is! ApiException || error.statusCode != 409) return null;
    if (nodes.length != 1) return null;
    final folder = _controller.restoreFolderFor(nodes.single);
    if (folder == null) return null;
    return SnackBarAction(
      label: 'Open folder',
      onPressed: () => context.go(AppRoutes.filesPath(folder)),
    );
  }

  Future<void> _deletePermanently(List<FileNode> nodes) async {
    if (nodes.isEmpty) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete permanently?',
      message:
          '${nodes.length == 1 ? '"${nodes.single.name}"' : _items(nodes.length)} '
          "will be deleted for good. This can't be undone.",
      confirmLabel: 'Delete permanently',
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await _controller.deletePermanently(nodes);
      if (mounted) _showMessage('Deleted ${_items(count)} for good');
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        Errors.message(
          e,
          nodes.length == 1 ? 'delete the item' : 'delete the items',
        ),
      );
    }
    unawaited(manualRefresh());
  }

  Future<void> _emptyTrash() async {
    final confirmed = await confirmAction(
      context,
      title: 'Empty trash?',
      message:
          "Everything in the trash will be deleted for good. This can't be "
          'undone.',
      confirmLabel: 'Empty trash',
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await _controller.empty();
      if (mounted) _showMessage('Deleted ${_items(count)} for good');
    } catch (e) {
      if (mounted) _showMessage(Errors.message(e, 'empty the trash'));
    }
    unawaited(manualRefresh());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final retentionDays = _controller.retentionDays;
        final location = _controller.location;
        return Scaffold(
          appBar: _controller.selectionMode
              ? null
              : QuarkAppBar(
                  label: 'Trash',
                  icon: QuarkIcons.delete_outline,
                  actions: [
                    // The whole trash, so only at its root: inside a folder
                    // it would read as emptying that folder.
                    if (location == null)
                      IconButton(
                        key: const ValueKey('trash_empty'),
                        tooltip: 'Empty trash',
                        icon: const Icon(Icons.delete_forever_outlined),
                        onPressed: (_controller.nodes?.isNotEmpty ?? false)
                            ? _emptyTrash
                            : null,
                      ),
                    // Selecting has always been here — long-press a row — but
                    // a long press is a gesture a mouse does not make, so on
                    // the web the trash looked like it had no bulk actions at
                    // all (#2250). An empty trash has nothing to select.
                    IconButton(
                      key: const ValueKey('trash_select'),
                      tooltip: 'Select items',
                      icon: const Icon(QuarkIcons.check_circle_outline),
                      onPressed: (_controller.nodes?.isNotEmpty ?? false)
                          ? _controller.enterSelection
                          : null,
                    ),
                    RefreshIconButton(
                      isRefreshing: isRefreshing,
                      onPressed: manualRefresh,
                    ),
                    const AppThemeToggle(),
                  ],
                ),
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.trash),
          body: Column(
            children: [
              if (_controller.selectionMode)
                FileSelectionBar(
                  selectedCount: _controller.selectedPaths.length,
                  totalCount: _controller.nodes?.length ?? 0,
                  onSelectAll: _controller.selectAll,
                  onDeselectAll: _controller.deselectAll,
                  onCancel: _controller.exitSelection,
                  // Always offered, so the bar keeps its shape; an empty
                  // selection restores nothing.
                  onRestore: () => _restore(_controller.selectedNodes),
                  onDelete: _controller.selectedPaths.isEmpty
                      ? null
                      : () => _deletePermanently(_controller.selectedNodes),
                  deleteTooltip: 'Delete permanently',
                ),
              if (location != null)
                FileBreadcrumbBar(
                  currentPath: _controller.breadcrumbPath!,
                  isSearchMode: false,
                  onGoHome: () => _go(null),
                  onGoUp: () => _go(TrashController.parentOf(location)),
                  onPathSelected: (path) => _go(_controller.locationAt(path)),
                ),
              if (location == null && _controller.devices.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: FileTopBarDeviceChips(
                    devices: _controller.devices,
                    activeDevicePaths: _controller.activeDevicePaths,
                    onDeviceToggled: _controller.toggleDevice,
                  ),
                ),
              Expanded(
                child: FileBrowserView(
                  // A fresh view per folder, so opening one shows a spinner
                  // rather than the last folder's rows until it loads.
                  key: ValueKey(location),
                  filesFuture: _controller.listing,
                  initialData: _controller.nodes,
                  isInitialLoad: isInitialLoad,
                  onFileMenuAction: _onMenuAction,
                  onOpenDirectory: _openFolder,
                  isGridView: false,
                  currentPath: '',
                  menuActions: _trashActions,
                  subtitleFor: _controller.subtitleFor,
                  selectionMode: _controller.selectionMode,
                  selectedPaths: _controller.selectedPaths,
                  onSelectionChanged: _controller.toggleSelection,
                  emptyBuilder: (_) => location != null
                      ? const EmptyStateWidget(
                          icon: QuarkIcons.folder_rounded,
                          headline: 'This folder is empty',
                        )
                      : EmptyStateWidget(
                          icon: QuarkIcons.delete_outline,
                          headline: 'Trash is empty',
                          subtext: retentionDays == null || retentionDays <= 0
                              ? 'Files you delete wait here until you restore them.'
                              : 'Files you delete wait here for $retentionDays '
                                    'days, then they are removed for good.',
                        ),
                  errorBuilder: (_, error) => EmptyStateWidget(
                    icon: QuarkIcons.delete_outline,
                    headline: Errors.somethingWentWrong,
                    subtext: Errors.message(error, 'load the trash'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
