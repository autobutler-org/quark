import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/view_grouping_copy.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The (i) beside the Files grouping toggle, in the wide bar and the compact
/// Views menu alike: it explains the unified and per-device views and the
/// device tags (#1871).
///
/// Probe key: `file_top_bar_grouping_help`.
class ViewGroupingHelpButton extends StatelessWidget {
  const ViewGroupingHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const QuarkHelpButton(
      key: ValueKey('file_top_bar_grouping_help'),
      title: ViewGroupingCopy.helpTitle,
      topics: ViewGroupingCopy.helpTopics,
      tooltip: 'About these views',
    );
  }
}
