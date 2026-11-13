import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_help_button/quark_help_dialog.dart';
import '../models/quark_help_topic.dart';

/// Explains chat encryption in household words: what a channel key is, how
/// members get it, and what "verified" and "unverified" mean. Shown from an
/// encryption line's "(?)" in `QuarkMessageList` and from
/// `QuarkEncryptionNotice`'s "What does this mean?".
///
/// The copy in a [QuarkHelpDialog]. It does not close itself: [onClose] fires
/// and the caller that pushed it pops it.
///
/// Key prefixes: the [QuarkHelpDialog]'s, `quark_help_topic_<index>` on each
/// topic and `quark_help_close` on the Close button.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) =>
///       QuarkEncryptionHelpDialog(onClose: () => Navigator.of(ctx).pop()),
/// );
/// ```
class QuarkEncryptionHelpDialog extends StatelessWidget {
  /// Creates the explainer.
  const QuarkEncryptionHelpDialog({required this.onClose, super.key});

  /// Called when the close button is tapped.
  final VoidCallback onClose;

  /// What the dialog says, in order.
  static const List<QuarkHelpTopic> topics = [
    QuarkHelpTopic(
      heading: 'Encryption',
      body:
          'Messages are scrambled on your device before they leave it, and only '
          'members of the channel can unscramble them. Not even the Quark '
          'itself can read them.',
    ),
    QuarkHelpTopic(
      heading: 'Keys',
      body:
          'Each channel has a key, a secret that unscrambles its messages. A '
          'member who has it shares it with new members automatically. A new '
          'key is made when someone leaves, so they can\'t read what comes '
          'after.',
    ),
    QuarkHelpTopic(
      heading: 'Verified and unverified',
      body:
          'A change is verified when Quark can confirm, by a digital signature, '
          'which member made it. Unverified means it had no signature, or one '
          'that didn\'t check out, so Quark can\'t vouch for who made it. '
          'Messages keep working. If no one in the channel expected the '
          'change, tell an admin.',
    ),
  ];

  @override
  Widget build(BuildContext context) => QuarkHelpDialog(
    title: 'How chat encryption works',
    icon: QuarkIcons.lock_outline,
    topics: topics,
    onClose: onClose,
  );
}
