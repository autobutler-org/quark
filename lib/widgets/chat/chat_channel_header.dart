import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open channel's name, and its topic when it has one, above its
/// messages.
class ChatChannelHeader extends StatelessWidget {
  /// Creates the header for channel [name].
  const ChatChannelHeader({required this.name, this.topic = '', super.key});

  /// The channel's name, shown after `#`.
  final String name;

  /// What the channel is for; empty shows nothing.
  final String topic;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '# $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (topic.isNotEmpty)
          Text(
            topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
          ),
      ],
    );
  }
}
