import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/slides/import/power_point_import_progress_dialog.dart';
import 'package:quark/widgets/slides/import/power_point_import_summary_dialog.dart';

/// Imports a PowerPoint file and opens the presentation it became (#1171):
/// the Slides page's Import PowerPoint and the file browser's "Open as
/// presentation" both end here.
///
/// [run] does the work — an import on the Quark, or an upload and then one —
/// while a [PowerPointImportProgressDialog] names [name]. A failure closes it
/// and says why in a snack bar. Otherwise, when anything was left out, a
/// [PowerPointImportSummaryDialog] lists it first, and then the presentation
/// opens at its URL, on [serial]'s drive when given.
///
/// Everything after the import goes through the root navigator, the router
/// and the messenger looked up before it, so the flow finishes even when
/// [context] — a file row — is rebuilt away while the Quark works.
Future<void> importPowerPointAndOpen(
  BuildContext context, {
  required String name,
  required Future<PowerPointImport> Function() run,
  String? serial,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PowerPointImportProgressDialog(name: name),
    ),
  );
  final PowerPointImport result;
  try {
    result = await run();
  } catch (e) {
    navigator.pop();
    messenger?.showSnackBar(
      SnackBar(content: Text(Errors.importPowerPoint(e))),
    );
    return;
  }
  navigator.pop();
  if (result.warnings.isNotEmpty && navigator.mounted) {
    await PowerPointImportSummaryDialog.show(navigator.context, result);
  }
  router.go(AppRoutes.slideFile(result.path, serial: serial));
}
