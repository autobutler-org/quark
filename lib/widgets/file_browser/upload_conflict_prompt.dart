import 'package:flutter/material.dart';
import 'package:quark/models/upload_conflict.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks what to do about [fileName], which the Quark says is already taken.
///
/// Returns the user's answer: keep both, replace, or — when they cancel or
/// dismiss the dialog — an answer with no choice, which leaves the file
/// unsent. [offerApplyToAll] shows the tick box that makes the answer stand
/// for the rest of the upload, for a batch with more than one file in it.
Future<UploadConflictAnswer> showUploadConflictDialog(
  BuildContext context,
  String fileName, {
  bool offerApplyToAll = false,
}) async {
  // The tick box is the one piece of state the dialog itself owns while it is
  // open, so it is held here rather than in the page or the package widget.
  var applyToAll = false;

  final choice = await showDialog<UploadConflictChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => UploadConflictDialog(
        fileName: fileName,
        showApplyToAll: offerApplyToAll,
        applyToAll: applyToAll,
        onApplyToAllChanged: (value) => setState(() => applyToAll = value),
        onKeepBoth: () => Navigator.of(ctx).pop(UploadConflictChoice.keepBoth),
        onReplace: () => Navigator.of(ctx).pop(UploadConflictChoice.replace),
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    ),
  );

  return UploadConflictAnswer(choice: choice, applyToAll: applyToAll);
}
