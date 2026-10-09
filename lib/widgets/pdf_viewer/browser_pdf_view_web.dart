import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Whether the browser shows PDFs itself: `navigator.pdfViewerEnabled`. It is
/// false where there is no inline viewer, as on most mobile browsers.
bool get browserHasPdfViewer => web.window.navigator.pdfViewerEnabled;

/// The PDF at [url] in the browser's own viewer, an iframe filling the space
/// it is given. The browser brings the scrolling, zoom, page controls, search
/// and printing its users already know.
///
/// An iframe cannot send an `Authorization` header, so [url] has to carry its
/// own credential, and the response has to be `inline` for the browser to show
/// it instead of saving it.
class BrowserPdfView extends StatelessWidget {
  /// Creates a browser viewer of the PDF at [url].
  const BrowserPdfView({required this.url, super.key});

  /// The PDF's URL, credential included.
  final Uri url;

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    // A new URL gets a new iframe; the element is only set up when created.
    key: ValueKey(url),
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLElement;
      frame.style.border = 'none';
      frame.setAttribute('src', url.toString());
    },
  );
}
