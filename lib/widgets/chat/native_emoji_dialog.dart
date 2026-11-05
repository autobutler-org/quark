import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Whether "More emoji" should ask the system keyboard instead of the in-app
/// catalog.
///
/// Android and iOS open the platform keyboard, which is where that system's
/// emoji keyboard lives. The web app, and desktop, keep the searchable
/// catalog: a browser text field does not open an emoji picker on its own.
/// [isWeb] and [platform] default to the ones Flutter is running on.
bool useNativeEmojiKeyboard({bool? isWeb, TargetPlatform? platform}) {
  if (isWeb ?? kIsWeb) return false;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// A scalar that makes its grapheme an emoji: the pictographic blocks, the
/// dingbats a heart and a star live in, and the mark on a digit. A joiner or
/// a variation selector on its own does not.
bool _marksEmoji(int rune) {
  if (rune == 0x200D || rune == 0xFE0F) return false;
  return rune == 0x20E3 ||
      rune == 0xA9 ||
      rune == 0xAE ||
      rune == 0x3030 ||
      rune == 0x303D ||
      rune == 0x3297 ||
      rune == 0x3299 ||
      (rune >= 0x2194 && rune <= 0x21AA) ||
      (rune >= 0x231A && rune <= 0x23FA) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x2934 && rune <= 0x2935) ||
      (rune >= 0x2B05 && rune <= 0x2B55) ||
      (rune >= 0x1F000 && rune <= 0x1FAFF);
}

/// The first emoji grapheme in [text], or null when [text] has none.
String? _firstEmojiGrapheme(String text) {
  for (final grapheme in text.characters) {
    if (grapheme.runes.any(_marksEmoji)) return grapheme;
  }
  return null;
}

/// Shows [NativeEmojiDialog] and resolves to the emoji typed, or null when
/// the dialog is canceled.
Future<String?> showNativeEmojiDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => NativeEmojiDialog(
      onPick: (emoji) => Navigator.of(dialogContext).pop(emoji),
      onCancel: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

/// Asks for one emoji through the platform keyboard.
///
/// A focused text field brings up the system keyboard. On Android and iOS
/// that keyboard has the emoji key, and neither platform offers an API that
/// selects the emoji keyboard for an app, so the field is how a reaction
/// reaches it. The first emoji typed is the result. Letters sit in the field
/// until an emoji arrives. Cancel, or a tap outside, chooses nothing.
///
/// It does not close itself: [onPick] and [onCancel] fire, and the caller
/// pops the route. [showNativeEmojiDialog] does that.
///
/// Key prefixes: `native_emoji_field` on the text field and
/// `native_emoji_cancel` on Cancel.
class NativeEmojiDialog extends StatefulWidget {
  /// Creates the dialog.
  const NativeEmojiDialog({
    required this.onPick,
    required this.onCancel,
    super.key,
  });

  /// Called once, with the first emoji typed.
  final ValueChanged<String> onPick;

  /// Called when Cancel is tapped.
  final VoidCallback onCancel;

  @override
  State<NativeEmojiDialog> createState() => _NativeEmojiDialogState();
}

class _NativeEmojiDialogState extends State<NativeEmojiDialog> {
  final _text = TextEditingController();
  var _picked = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_picked) return;
    final emoji = _firstEmojiGrapheme(value);
    if (emoji == null) return;
    _picked = true;
    widget.onPick(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add reaction'),
      content: TextField(
        key: const ValueKey('native_emoji_field'),
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Choose an emoji from the keyboard',
        ),
        onChanged: _onChanged,
      ),
      actions: [
        TextButton(
          key: const ValueKey('native_emoji_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
