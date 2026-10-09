import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/pdf_viewer/browser_pdf_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A full-screen viewer for a PDF on the Quark, with Download and, off web,
/// "Open with…" in the top bar (#1184).
///
/// On web the browser's own PDF viewer shows it, in a [BrowserPdfView]: it
/// scrolls and zooms better than anything drawn into the app's canvas, and
/// brings its own page controls. Its iframe cannot send a header, so it loads
/// the same token-carrying media URL the video player does.
///
/// Everywhere else, and in a browser with no PDF viewer of its own, pdfrx
/// draws the pages in a scrolling, zoomable column with its scroll thumb,
/// which shows the page number. pdfrx reads the download endpoint itself,
/// authenticated by the session's `Authorization` header. Off web it asks for
/// byte ranges, so a large PDF opens before it has all arrived. In a browser
/// it fetches the whole file: pdfrx's range mode there starts with a `HEAD`
/// request, which the download endpoint does not answer.
///
/// Key prefixes: `pdf_viewer_download`, `pdf_viewer_open_with`.
class PdfViewerPage extends StatefulWidget {
  /// The file's path on the Quark.
  final String filePath;

  /// The device the file is on; null lets the Quark pick.
  final String? serial;

  /// The file name shown in the app bar and used for a download.
  final String name;

  /// Closes the viewer from its back button. Null leaves the app bar's own,
  /// which pops the route this viewer was pushed on.
  final VoidCallback? onClose;

  const PdfViewerPage({
    super.key,
    required this.filePath,
    required this.name,
    this.serial,
    this.onClose,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  bool _downloading = false;
  bool _opening = false;

  final _controller = PdfViewerController();

  /// Built once: pdfrx compares its builders by identity, so fresh closures
  /// on every rebuild would read as changed parameters.
  late final PdfViewerParams _params = PdfViewerParams(
    // pdfrx's default moves a fifth of what the wheel asked for, which reads
    // as a stuck page next to any other scrolling surface.
    scrollByMouseWheel: 1,
    viewerOverlayBuilder: (_, _, _) => [
      PdfViewerScrollThumb(controller: _controller),
    ],
    loadingBannerBuilder: (_, _, _) => const Center(child: QuarkLoader()),
    errorBannerBuilder: (_, error, _, _) => EmptyStateWidget(
      icon: QuarkIcons.broken_image_outlined,
      headline: Errors.message(error, 'open the file'),
    ),
  );

  Future<void> _download() async {
    setState(() => _downloading = true);
    await downloadViewedFile(
      context,
      path: widget.filePath,
      serial: widget.serial,
      name: widget.name,
    );
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _openWith() async {
    setState(() => _opening = true);
    await openViewedFileWithSystem(
      context,
      path: widget.filePath,
      serial: widget.serial,
      name: widget.name,
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChromeAppBar(
        leading: widget.onClose == null
            ? null
            : BackButton(onPressed: widget.onClose),
        title: Text(widget.name),
        actions: [
          QuarkBarIconButton(
            key: const ValueKey('pdf_viewer_download'),
            icon: QuarkIcons.download_outlined,
            tooltip: 'Download',
            isBusy: _downloading,
            onPressed: _download,
          ),
          if (!kIsWeb)
            QuarkBarIconButton(
              key: const ValueKey('pdf_viewer_open_with'),
              icon: QuarkIcons.open_in_new,
              tooltip: 'Open with…',
              isBusy: _opening,
              onPressed: _openWith,
            ),
          const AppThemeToggle(),
        ],
      ),
      body: browserHasPdfViewer
          ? BrowserPdfView(
              url: FilesService.constructMediaUrl(
                widget.filePath,
                serial: widget.serial,
              ),
            )
          : PdfViewer.uri(
              FilesService.downloadUrl(widget.filePath, serial: widget.serial),
              headers: FilesService.instance.authHeaders,
              // Range mode in a browser needs a HEAD the Quark does not answer.
              preferRangeAccess: !kIsWeb,
              controller: _controller,
              params: _params,
            ),
    );
  }
}
