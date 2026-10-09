/// The browser's own PDF viewer in an iframe, and whether the browser has
/// one. The web build gets the real thing; every other build gets a stand-in
/// that says no, so `PdfViewerPage` falls back to pdfrx (#1184).
library;

export 'package:quark/widgets/pdf_viewer/browser_pdf_view_stub.dart'
    if (dart.library.js_interop) 'package:quark/widgets/pdf_viewer/browser_pdf_view_web.dart';
