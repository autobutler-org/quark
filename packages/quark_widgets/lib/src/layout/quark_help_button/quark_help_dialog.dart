import 'package:material_ui/material_ui.dart';

import '../../models/quark_help_topic.dart';
import '../../theme/quark_tokens.dart';
import 'quark_help_topic_row.dart';

/// The explanation a `QuarkHelpButton` opens: a [title] and the caller's
/// [topics], in order, with one Close action.
///
/// The content scrolls when it is taller than the screen. Close pops the
/// route the dialog was shown in, so it is meant for [showDialog].
///
/// Key prefixes: `quark_help_topic_<index>` on each topic row, counted from
/// 0 in [topics] order, and `quark_help_close` on the Close button.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (_) => const QuarkHelpDialog(
///     title: 'Views',
///     topics: [QuarkHelpTopic(heading: 'Unified', body: '...')],
///   ),
/// );
/// ```
class QuarkHelpDialog extends StatelessWidget {
  /// Creates the dialog titled [title], explaining [topics].
  const QuarkHelpDialog({required this.title, required this.topics, super.key});

  /// The dialog's title.
  final String title;

  /// What the dialog explains, in order.
  final List<QuarkHelpTopic> topics;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingMd,
          children: [
            for (final (index, topic) in topics.indexed)
              QuarkHelpTopicRow(
                key: ValueKey('quark_help_topic_$index'),
                topic: topic,
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('quark_help_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
