import 'package:flutter/foundation.dart';

/// One chat channel as the chat widgets need it: its id, its name, and
/// whether it is shared with only some people.
///
/// The package's own view of a channel, so no widget imports the app's model.
/// Callbacks come back out with the [id].
@immutable
class ChatChannelItem {
  /// Creates a channel value.
  const ChatChannelItem({
    required this.id,
    required this.name,
    this.isPrivate = false,
  });

  /// The channel's id on the Quark, and what callbacks carry.
  final String id;

  /// The channel's name, shown without a leading `#`.
  final String name;

  /// Whether the channel is shared with only some people rather than with
  /// everyone on the Quark. Private channels show a lock.
  final bool isPrivate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatChannelItem &&
          other.id == id &&
          other.name == name &&
          other.isPrivate == isPrivate;

  @override
  int get hashCode => Object.hash(id, name, isPrivate);
}
