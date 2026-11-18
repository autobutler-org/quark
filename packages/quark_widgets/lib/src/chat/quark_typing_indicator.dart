import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// One muted line saying who else is typing in a channel (#2426): "ada is
/// typing", "ada and bob are typing", or "Several people are typing" past
/// two. With no [names] it takes no space.
///
/// Who is typing, and when that lapses, is the caller's. Nothing animates,
/// so there is nothing for reduced motion to turn off, and a screen reader
/// hears the line as a live region when it changes.
///
/// Key prefix: `typing_indicator` on the line.
///
/// ```dart
/// QuarkTypingIndicator(names: controller.typingNames);
/// ```
class QuarkTypingIndicator extends StatelessWidget {
  /// Creates the line for [names].
  const QuarkTypingIndicator({required this.names, super.key});

  /// The others typing now, in the order to name them.
  final List<String> names;

  /// The sentence for [names]; empty when nobody is typing.
  static String sentence(List<String> names) => switch (names) {
    [] => '',
    [final one] => '$one is typing',
    [final one, final two] => '$one and $two are typing',
    _ => 'Several people are typing',
  };

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final tokens = QuarkTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
        child: Text(
          sentence(names),
          key: const ValueKey('typing_indicator'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.mutedForeground,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
