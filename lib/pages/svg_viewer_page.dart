import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
/// [bytes] is the raw file content and [name] the file name shown in the app
/// bar.
class SvgViewerPage extends StatelessWidget {
  final Uint8List bytes;
  final String name;

  const SvgViewerPage({super.key, required this.bytes, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name), actions: const [AppThemeToggle()]),
      body: QuarkCheckerboard(
        child: InteractiveViewer(
          child: Center(child: SvgPicture.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
