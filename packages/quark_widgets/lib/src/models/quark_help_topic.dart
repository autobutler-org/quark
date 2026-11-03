import 'package:flutter/widgets.dart';

/// One titled paragraph a `QuarkHelpDialog` explains, such as what one view
/// of a page shows.
///
/// The caller writes the copy; the package only lays it out.
class QuarkHelpTopic {
  /// Creates a topic headed [heading] that reads [body].
  const QuarkHelpTopic({required this.heading, required this.body, this.icon});

  /// The topic's short bold heading.
  final String heading;

  /// The paragraph under [heading].
  final String body;

  /// An optional glyph from `QuarkIcons` drawn before the topic, or null for
  /// none.
  final IconData? icon;
}
