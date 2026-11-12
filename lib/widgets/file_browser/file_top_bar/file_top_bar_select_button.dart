import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Enters multi-select. It sits in the bar's second row, pinned at every
/// width, so the top row fits a phone (#3454).
///
/// Selecting used to be a long press on a row, a gesture a mouse does not
/// make, so on the web the whole feature was invisible (#2057). This button is
/// the only way in now that a long press opens the row's menu instead (#2245).
///
/// Probe keys: `file_top_bar_select`.
class FileTopBarSelectButton extends StatelessWidget {
  const FileTopBarSelectButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return QuarkBarIconButton(
      key: const ValueKey('file_top_bar_select'),
      icon: QuarkIcons.check_circle_outline,
      tooltip: 'Select',
      onPressed: onPressed,
    );
  }
}
