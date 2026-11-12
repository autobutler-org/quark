import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/markdown_viewer_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/markdown_viewer/markdown_viewer_image.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Markdown viewer's rendered surface: the disconnected state when the
/// Quark cannot be reached, otherwise a [QuarkMarkdownView] fed from
/// [controller], with images drawn by [MarkdownViewerImage].
class MarkdownViewerBody extends StatelessWidget {
  /// The rendered view's state; the caller rebuilds this widget when it
  /// changes.
  final MarkdownViewerController controller;

  /// Called with a link's address, as written in the file, when it is tapped.
  final ValueChanged<String> onLinkTap;

  const MarkdownViewerBody({
    required this.controller,
    required this.onLinkTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error != null && isQuarkUnreachableError(error)) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: controller.load,
      );
    }
    final total = controller.totalSize;
    return QuarkMarkdownView(
      document: controller.document,
      isLoading: controller.isLoading,
      error: error == null ? null : Errors.message(error, 'load the file'),
      onRetry: controller.load,
      onLinkTap: onLinkTap,
      imageBuilder: (context, src, alt) => MarkdownViewerImage(
        src: src,
        alt: alt,
        filePath: controller.path,
        serial: controller.serial,
        remoteAllowed: controller.allowedRemoteImages.contains(src),
        onAllowRemote: () => controller.allowRemoteImage(src),
      ),
      statusLabel: controller.isTruncated && total != null
          ? 'Showing the first '
                '${StorageDevice.formatBytes(controller.loadedBytes)} of '
                '${StorageDevice.formatBytes(total)}. View the source to '
                'read the rest.'
          : null,
    );
  }
}
