import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';

/// A heading over one group of a `QuarkChannelList`'s rows, such as "Direct
/// messages" or "Other channels".
///
/// A part of `QuarkChannelList`, tested through it. It takes its key from
/// the list.
class ChatChannelListHeading extends StatelessWidget {
  /// Creates the heading reading [label].
  const ChatChannelListHeading({required this.label, super.key});

  /// The heading's text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacingSm,
        tokens.spacingMd,
        tokens.spacingSm,
        tokens.spacingXs,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: tokens.mutedForeground),
      ),
    );
  }
}
