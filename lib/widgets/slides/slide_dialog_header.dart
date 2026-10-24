import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A slide editor dialog's title row: [title] as a heading, and a close
/// button that pops the dialog.
///
/// Key prefixes: [closeKey] on the close button, such as
/// `slide_chart_data_close`.
class SlideDialogHeader extends StatelessWidget {
  /// The row for a dialog called [title].
  const SlideDialogHeader({
    required this.title,
    required this.closeKey,
    super.key,
  });

  /// The dialog's name.
  final String title;

  /// The close button's `ValueKey` name.
  final String closeKey;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      QuarkBarIconButton(
        key: ValueKey(closeKey),
        icon: QuarkIcons.close,
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}
