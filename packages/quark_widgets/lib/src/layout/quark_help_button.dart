import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/quark_help_topic.dart';
import 'quark_bar_icon_button.dart';
import 'quark_help_button/quark_help_dialog.dart';

/// A bar (i) button that opens a [QuarkHelpDialog] explaining [topics], for a
/// control whose meaning is not obvious at a glance, such as Files' unified
/// and per-device views.
///
/// It is a [QuarkBarIconButton] showing `QuarkIcons.info_outline`, so it sits
/// in a top bar beside the control it explains. The caller writes every word
/// of the explanation; the package supplies only the default [tooltip] and
/// the dialog's Close label.
///
/// Key prefixes: none of its own. The caller's `key` sits on this widget,
/// whose whole area is the button, so `tap #<key>` opens the dialog. The
/// dialog keys its rows `quark_help_topic_<index>` and its Close button
/// `quark_help_close`.
///
/// ```dart
/// QuarkHelpButton(
///   key: const ValueKey('files_view_help'),
///   title: 'Unified and per-device views',
///   topics: const [
///     QuarkHelpTopic(heading: 'Unified', body: 'Every drive in one list.'),
///     QuarkHelpTopic(heading: 'Per-device', body: 'One drive at a time.'),
///   ],
/// );
/// ```
class QuarkHelpButton extends StatelessWidget {
  /// Creates a help button whose dialog is titled [title] and explains
  /// [topics].
  const QuarkHelpButton({
    required this.title,
    required this.topics,
    this.tooltip = 'Help',
    super.key,
  });

  /// The dialog's title.
  final String title;

  /// What the dialog explains, in order.
  final List<QuarkHelpTopic> topics;

  /// The button's tooltip and screen reader label.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return QuarkBarIconButton(
      icon: QuarkIcons.info_outline,
      tooltip: tooltip,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => QuarkHelpDialog(title: title, topics: topics),
      ),
    );
  }
}
