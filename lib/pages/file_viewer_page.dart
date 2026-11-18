import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/photo_preview_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/layout/file_viewer_chrome.dart';
import 'package:quark/widgets/layout/file_viewer_unavailable.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The page at `/view/<path>`: the viewer for one file, picked by its kind.
///
/// Every kind with an in-app viewer opens here rather than being pushed over
/// the file browser, so the address bar names the file, a reload or a shared
/// link reopens it, and browser back closes it (#2328). Docs, sheets and text
/// never get here: `viewFileRedirect` sends them to their editors.
///
/// Closing the viewer — its back button, Escape in the photo viewer, a system
/// back — replaces this history entry with the page the URL's `?from=` names
/// (#1678), or the file's folder without one, so browser back from there
/// never bounces into the viewer again.
///
/// A photo opens at once, then steps through the other photos in its folder,
/// by name as Files lists them, once the folder's listing lands; a listing
/// that fails leaves it the one photo (#3378, #3379). Each step replaces the
/// address bar's entry with the photo's own `/view` URL rather than adding
/// one, so a reload reopens the photo on screen and back still closes the
/// viewer.
///
/// A photo shows its screen-sized preview first, and its neighbors are
/// prefetched as previews: a few hundred KB each rather than the several MB
/// of an original. The original is downloaded only once the user zooms in,
/// or copies the photo; a photo the Quark has no preview for, such as a
/// HEIC, falls back to the original (#4220).
///
/// A PDF, video or audio file is loaded by the browser or the player straight
/// from its URL, which never shows the app a refusal: an unplugged drive's
/// PDF came up as the Quark's JSON in the browser's own viewer (#3981). So
/// those kinds ask the Quark about the file first, and a file it cannot hand
/// over opens [FileViewerUnavailable], which says why, instead of a viewer.
class FileViewerPage extends StatefulWidget {
  /// The file's path on the Quark, as the route's `:path` delivers it.
  final String filePath;

  /// The device the file is on; empty lets the Quark pick.
  final String serial;

  /// Fetches an SVG's markup, and the photos a photo steps to. A parameter so
  /// a test can answer without a Quark.
  final Future<Uint8List?> Function(String filePath, {String? serial})
  downloadBytes;

  /// Fetches a photo's screen-sized preview, shown before the original. A
  /// parameter so a test can answer without a Quark.
  final Future<Uint8List?> Function(String filePath, {String? serial})
  downloadPreview;

  /// Lists the folder a photo steps through. A parameter so a test can answer
  /// without a Quark.
  final Future<List<FileNode>> Function(String path, {List<String>? serials})
  listFiles;

  /// Asks the Quark about a file a viewer would load from its URL, and throws
  /// when it cannot hand the file over. A parameter so a test can answer
  /// without a Quark.
  final Future<void> Function(String filePath, {String? serial}) statFile;

  const FileViewerPage({
    super.key,
    required this.filePath,
    this.serial = '',
    this.downloadBytes = FilesService.downloadFileBytes,
    this.downloadPreview = PhotoPreviewService.downloadPreviewBytes,
    this.listFiles = FilesService.getFiles,
    this.statFile = FilesService.statFile,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late final String _name = widget.filePath.split('/').last;
  late final FileKind _kind = fileKindForName(_name);
  late final String? _serial = widget.serial.isEmpty ? null : widget.serial;

  /// SVG is XML for `SvgPicture`, not bytes the photo viewer fetches itself
  /// (#1806), so this page fetches it.
  late final Future<Uint8List?>? _svgBytes = _kind == FileKind.svg
      ? widget.downloadBytes(widget.filePath, serial: _serial)
      : null;

  /// Whether the Quark has the file, for a kind whose viewer loads it from a
  /// URL and so never sees a refusal; null for every other kind.
  late final Future<void>? _available =
      const {FileKind.pdf, FileKind.video, FileKind.audio}.contains(_kind)
      ? widget.statFile(widget.filePath, serial: _serial)
      : null;

  late final Uri _mediaUrl = FilesService.constructMediaUrl(
    widget.filePath,
    serial: _serial,
  );

  late final String _folder = widget.filePath.contains('/')
      ? widget.filePath.substring(0, widget.filePath.lastIndexOf('/'))
      : '';

  /// The names of the folder's photos in the order Files lists them, this one
  /// among them. Null until the listing lands, and for good when it fails.
  List<String>? _photos;

  /// A system back reaches both this page's scope and the photo viewer's own.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    if (_kind == FileKind.image) _listPhotos();
  }

  /// Lists the photo's folder for the photos either side of it. Only the
  /// photo's own drive counts: every sibling carries the folder's serial.
  Future<void> _listPhotos() async {
    final List<FileNode> nodes;
    try {
      nodes = await widget.listFiles(
        _folder,
        serials: _serial == null ? null : [_serial],
      );
    } catch (e) {
      debugPrint('FileViewerPage: failed to list $_folder: $e');
      return;
    }
    // Files' default order: by name, ignoring case.
    final photos = [
      for (final node in nodes)
        if (!node.isDir &&
            node.deviceSerial == widget.serial &&
            fileKindForName(node.name) == FileKind.image)
          node.name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!mounted || !photos.contains(_name)) return;
    setState(() => _photos = photos);
  }

  String _photoPath(int index) =>
      _folder.isEmpty ? _photos![index] : '$_folder/${_photos![index]}';

  Future<(Uint8List?, String, String?, String?)> _loadPhoto(int index) async {
    final bytes = await _photoBytes(index);
    return (bytes, _photos![index], _photoPath(index), _serial);
  }

  Future<Uint8List?> _photoBytes(int index) =>
      _previewBytes(_photoPath(index), serial: _serial);

  /// The preview of the photo at [path], or its original when the Quark
  /// answers without one. A request that never got an answer is thrown, so
  /// the viewer offers a retry rather than spending the original's bytes.
  Future<Uint8List?> _previewBytes(String path, {String? serial}) =>
      PhotoBytesCache.instance.fetch(
        PhotoBytesCache.previewKey(path, serial),
        () async {
          try {
            return await widget.downloadPreview(path, serial: serial);
          } on ApiException catch (e) {
            debugPrint('FileViewerPage: no preview of $path: $e');
            return _originalBytes(path, serial: serial);
          }
        },
      );

  Future<Uint8List?> _originalBytes(String path, {String? serial}) =>
      PhotoBytesCache.instance.fetch(
        PhotoBytesCache.key(path, serial),
        () => widget.downloadBytes(path, serial: serial),
      );

  /// Puts the photo the viewer stepped to in the address bar, in place of
  /// this entry: browser history holds the viewer once, however many photos
  /// it showed. The router is not told, so this page and the viewer stay.
  void _showInAddressBar(int index) {
    final from = GoRouterState.of(
      context,
    ).uri.queryParameters[AppRoutes.editorFromParam];
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(
        AppRoutes.viewFilePath(
          _photoPath(index),
          serial: widget.serial,
          from: from,
        ),
      ),
      replace: true,
    );
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    Router.neglect(
      context,
      () => context.go(
        AppRoutes.leaveFile(context, widget.filePath, serial: widget.serial),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: FutureBuilder<void>(
        future: _available,
        builder: (context, available) => switch (_kind) {
          _ when available.hasError => FileViewerUnavailable(
            name: _name,
            error: available.error,
            onClose: _close,
          ),
          _
              when _available != null &&
                  available.connectionState != ConnectionState.done =>
            FileViewerChrome(
              name: _name,
              onClose: _close,
              body: const Center(child: QuarkLoader()),
            ),
          FileKind.image => ImageViewerPage(
            name: _name,
            relPath: widget.filePath,
            serial: _serial,
            initialIndex: _photos?.indexOf(_name) ?? 0,
            imageCount: _photos?.length ?? 1,
            onLoadImage: _photos == null ? null : _loadPhoto,
            onPrefetchImage: _photos == null ? null : _photoBytes,
            loadBytes: _previewBytes,
            loadOriginal: _originalBytes,
            onImageShown: _showInAddressBar,
            onClose: _close,
          ),
          FileKind.svg => FutureBuilder<Uint8List?>(
            future: _svgBytes,
            builder: (context, snapshot) => SvgViewerPage(
              bytes: snapshot.data,
              name: _name,
              error:
                  snapshot.connectionState == ConnectionState.done &&
                      snapshot.data == null
                  ? Errors.message(snapshot.error, 'open the file')
                  : null,
              onClose: _close,
            ),
          ),
          // Audio has no video track, so the video viewer paints only its black
          // backdrop (#1573).
          FileKind.audio => AudioPlayerPage(
            url: _mediaUrl,
            name: _name,
            onClose: _close,
          ),
          FileKind.video => VideoViewerPage(
            url: _mediaUrl,
            name: _name,
            onClose: _close,
          ),
          FileKind.pdf => PdfViewerPage(
            filePath: widget.filePath,
            serial: _serial,
            name: _name,
            onClose: _close,
          ),
          _ => GenericFileViewerPage(
            node: FileNode(
              name: _name,
              size: 0,
              isDir: false,
              deviceName: '',
              devicePath: '',
              deviceSerial: widget.serial,
              dirPath: widget.filePath,
            ),
            onClose: _close,
          ),
        },
      ),
    );
  }
}
