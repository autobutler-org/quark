import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's bar action that saves the presentation as a PowerPoint
/// file (#1172): a download glyph explained by its tooltip, which is also
/// what a screen reader announces it as. While [isExporting] it shows a spinner and
/// refuses taps, so an export runs once however often it is tapped.
///
/// Key prefixes: `slide_editor_export_pptx` on the button.
///
/// ```dart
/// SlideExportButton(
///   isExporting: controller.isExporting,
///   onPressed: controller.exportPptx,
/// );
/// ```
class SlideExportButton extends StatelessWidget {
  /// Creates the button; a null [onPressed] shows it disabled.
  const SlideExportButton({
    required this.isExporting,
    required this.onPressed,
    super.key = const ValueKey('slide_editor_export_pptx'),
  });

  /// What the tooltip and a screen reader call the action.
  static const label = 'Export as PowerPoint (.pptx)';

  /// Whether an export is running.
  final bool isExporting;

  /// Starts the export; null while there is no presentation to export.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => QuarkBarIconButton(
    icon: QuarkIcons.download_outlined,
    tooltip: label,
    isBusy: isExporting,
    onPressed: onPressed,
  );
}
