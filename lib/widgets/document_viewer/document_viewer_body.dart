import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/document_viewer_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/document_viewer/document_viewer_image.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The document viewer's surface: the disconnected state when the Quark
/// cannot be reached, otherwise a [QuarkDocumentView] fed from [controller],
/// with pictures drawn by [DocumentViewerImage].
class DocumentViewerBody extends StatelessWidget {
  /// The viewer's state; the caller rebuilds this widget when it changes.
  final DocumentViewerController controller;

  /// Called with a link's address, as the document wrote it, when it is
  /// tapped.
  final ValueChanged<String> onLinkTap;

  const DocumentViewerBody({
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
    return QuarkDocumentView(
      document: controller.document,
      isLoading: controller.isLoading,
      error: error == null ? null : Errors.message(error, 'open the document'),
      onRetry: controller.load,
      onLinkTap: onLinkTap,
      imageBuilder: (context, image) => DocumentViewerImage(
        image: image,
        filePath: controller.path,
        serial: controller.serial,
      ),
    );
  }
}
