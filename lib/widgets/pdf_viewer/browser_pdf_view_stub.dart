import 'package:flutter/widgets.dart';

/// Whether the browser shows PDFs itself. Off web there is no browser, so no.
bool get browserHasPdfViewer => false;

/// The non-web stand-in for the browser's PDF viewer. It is never built:
/// [browserHasPdfViewer] is false here, so `PdfViewerPage` uses pdfrx.
class BrowserPdfView extends StatelessWidget {
  /// Creates the stand-in for a viewer of the PDF at [url].
  const BrowserPdfView({required this.url, super.key});

  /// The PDF's URL.
  final Uri url;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
