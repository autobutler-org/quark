import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/markdown_viewer_files.dart';
import 'package:quark/utils/svg_viewport.dart';
import 'package:quark_icons/quark_icons.dart';

/// An image in a Markdown file (#2987).
///
/// One on the Quark — a relative address, resolved against the file's folder
/// — loads through the download endpoint. One on the web is not fetched
/// until the reader taps "Load remote image": loading it tells that server
/// who opened the file. Anything else (`data:`, an address that does not
/// parse) shows its alt text, as does one that fails to load or decode.
///
/// An address whose path ends in `.svg` renders through `flutter_svg`, since
/// `Image.network` decodes raster formats only; `svgWithViewport` sizes a root
/// that declares no usable size. Scripts in the SVG never run and its own
/// external references are never fetched.
///
/// Key prefix: `markdown_viewer_load_image_<src>` on the load button.
class MarkdownViewerImage extends StatelessWidget {
  /// The image's address, as written in the file.
  final String src;

  /// The image's alt text, shown when it cannot be or has not been loaded.
  final String alt;

  /// The Markdown file's files-relative path, which [src] is relative to.
  final String filePath;

  /// The device the file is on, null for the internal drive.
  final String? serial;

  /// Whether the reader has asked for this remote image to load.
  final bool remoteAllowed;

  /// Called when the reader taps the load button of a remote image.
  final VoidCallback onAllowRemote;

  const MarkdownViewerImage({
    required this.src,
    required this.alt,
    required this.filePath,
    required this.onAllowRemote,
    this.serial,
    this.remoteAllowed = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final target = resolveMarkdownLink(filePath, src);
    final fallback = Text(alt.isEmpty ? src : alt);
    Widget onError(BuildContext context, Object error, StackTrace? stack) =>
        fallback;
    // ponytail: SVG is picked by extension, so an SVG served from a path
    // without one (some badge services) shows its alt text. Sniff the
    // response's content type if that matters.
    Widget network(String url, String path, {Map<String, String>? headers}) =>
        path.toLowerCase().endsWith('.svg')
        ? SvgPicture(
            _SizedSvgLoader(url, headers: headers),
            semanticsLabel: alt,
            errorBuilder: onError,
          )
        : Image.network(
            url,
            headers: headers,
            semanticLabel: alt,
            errorBuilder: onError,
          );
    switch (target.kind) {
      case MarkdownLinkKind.file:
        return network(
          FilesService.downloadUrl(target.value, serial: serial).toString(),
          target.value,
          headers: FilesService.instance.authHeaders,
        );
      case MarkdownLinkKind.remote:
        if (remoteAllowed) {
          return network(target.value, Uri.parse(target.value).path);
        }
        return Tooltip(
          message: target.value,
          child: OutlinedButton.icon(
            key: ValueKey('markdown_viewer_load_image_$src'),
            onPressed: onAllowRemote,
            icon: const Icon(QuarkIcons.image_outlined),
            label: Text(
              alt.isEmpty ? 'Load remote image' : 'Load remote image: $alt',
            ),
          ),
        );
      case MarkdownLinkKind.other:
        return fallback;
    }
  }
}

/// Fetches an SVG like [SvgNetworkLoader] and hands the markup through
/// [svgWithViewport] first, so a root sized `100%` or not at all still lays
/// out in the text.
class _SizedSvgLoader extends SvgNetworkLoader {
  const _SizedSvgLoader(super.url, {super.headers});

  @override
  String provideSvg(Uint8List? message) =>
      svgWithViewport(super.provideSvg(message));
}
