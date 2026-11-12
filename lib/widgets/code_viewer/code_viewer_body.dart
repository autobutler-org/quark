import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The code viewer's surface: the disconnected state when the Quark cannot be
/// reached, otherwise a [QuarkCodeViewer] fed from [controller].
class CodeViewerBody extends StatelessWidget {
  /// The state to render; the caller rebuilds this widget when it changes.
  final CodeViewerController controller;

  const CodeViewerBody({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error != null && isQuarkUnreachableError(error)) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: controller.load,
      );
    }
    final loadMoreError = controller.loadMoreError;
    final total = controller.totalSize;
    return QuarkCodeViewer(
      lines: controller.lines,
      language: controller.language,
      isLoading: controller.isLoading,
      error: error == null ? null : Errors.message(error, 'load the file'),
      onRetry: controller.load,
      wrap: controller.wrap,
      onWrapChanged: controller.setWrap,
      searchQuery: controller.searchQuery,
      onSearchChanged: controller.setSearchQuery,
      matches: controller.matches,
      activeMatch: controller.activeMatch,
      onNextMatch: controller.nextMatch,
      onPreviousMatch: controller.previousMatch,
      hasMore: controller.hasMore,
      isLoadingMore: controller.isLoadingMore,
      loadMoreError: loadMoreError == null
          ? null
          : Errors.message(loadMoreError, 'load more of the file'),
      onLoadMore: controller.loadMore,
      statusLabel: controller.hasMore && total != null
          ? 'Showing ${StorageDevice.formatBytes(controller.loadedBytes)} '
                'of ${StorageDevice.formatBytes(total)}'
          : null,
    );
  }
}
