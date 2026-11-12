import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/svg_viewport.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A full-screen viewer for a single SVG.
///
/// SVG is XML rather than a raster codec, so it cannot go through
/// `ImageViewerPage`, whose `Image.memory` only decodes PNG/JPEG/GIF/WebP/BMP
/// and shows a broken image for anything else (#1806). [SvgPicture] renders the
/// markup instead, and [InteractiveViewer] gives the same pinch/scroll zoom the
/// photo viewer has.
///
/// A [QuarkCheckerboard] sits behind the artwork so transparent regions read as
/// transparent rather than as the page background — and it sits outside the
/// [InteractiveViewer], so the backdrop stays put while the artwork pans and
/// zooms over it.
///
/// The artwork is scaled to fill the body whatever size it declares: a vector
/// has no native resolution, so a 16 pixel icon is not shown at 16 pixels. A
/// root that declares no usable size gets one from [svgWithViewport] first.
/// Markup the decoder rejects shows an error in place of the artwork. Scripts
/// are never run and external references never fetched — `flutter_svg` draws
/// the shapes and skips the rest.
///
/// [bytes] is the raw file content and [name] the file name shown in the app
/// bar. Null [bytes] is still loading, unless [error] says why it never will.
class SvgViewerPage extends StatelessWidget {
  final Uint8List? bytes;
  final String name;

  /// Why [bytes] could not be loaded, already written for the user.
  final String? error;

  /// Closes the viewer from its back button. Null leaves the app bar's own,
  /// which pops the route this viewer was pushed on.
  final VoidCallback? onClose;

  const SvgViewerPage({
    super.key,
    required this.bytes,
    required this.name,
    this.error,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    final error = this.error;
    return Scaffold(
      appBar: ChromeAppBar(
        leading: onClose == null ? null : BackButton(onPressed: onClose),
        title: Text(name),
        actions: const [AppThemeToggle()],
      ),
      body: switch ((bytes, error)) {
        (_, final String error) => EmptyStateWidget(
          icon: QuarkIcons.broken_image_outlined,
          headline: error,
        ),
        (null, _) => const Center(child: QuarkLoader()),
        (final Uint8List bytes, _) => QuarkCheckerboard(
          child: InteractiveViewer(
            child: SizedBox.expand(
              child: SvgPicture.string(
                svgWithViewport(utf8.decode(bytes, allowMalformed: true)),
                placeholderBuilder: (context) =>
                    const Center(child: QuarkLoader()),
                errorBuilder: (context, error, stackTrace) => EmptyStateWidget(
                  icon: QuarkIcons.broken_image_outlined,
                  headline: Errors.couldNot('show this SVG'),
                ),
              ),
            ),
          ),
        ),
      },
    );
  }
}
