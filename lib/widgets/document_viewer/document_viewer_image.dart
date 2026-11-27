import 'package:material_ui/material_ui.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A picture inside a document (#3265), loaded from the Quark's part
/// endpoint, which serves only PNG, JPEG, GIF, WebP and BMP out of the
/// document's media folder.
///
/// One the endpoint refuses or this device cannot decode (EMF and WMF clip
/// art, mostly) shows its alt text. A picture the document only links to
/// never reaches this widget: `QuarkDocumentView` draws its placeholder and
/// nothing is fetched.
class DocumentViewerImage extends StatelessWidget {
  /// The image block; its `part` names the entry inside the document.
  final QuarkDocumentImage image;

  /// The document's files-relative path.
  final String filePath;

  /// The device the document is on, null for the internal drive.
  final String? serial;

  const DocumentViewerImage({
    required this.image,
    required this.filePath,
    this.serial,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Image.network(
      previewPartUrl(
        image.part ?? '',
        filePath: filePath,
        serial: serial,
      ).toString(),
      semanticLabel: image.alt,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => Text(
        image.alt.isEmpty ? 'Image not shown' : image.alt,
        style: TextStyle(color: tokens.mutedForeground),
      ),
    );
  }
}
