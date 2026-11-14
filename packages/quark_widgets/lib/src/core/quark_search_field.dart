import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_menu_label.dart';

/// The one search box: a dense filled field with a search glyph in front and
/// a close button at its end.
///
/// The field owns the look: the [QuarkTokens.input] fill, a
/// [QuarkTokens.radiusMd] edge in [QuarkTokens.border], and both glyphs at
/// the bar glyph size. The caller owns the words and what the button does.
/// [onDismiss] either clears the text or leaves search mode, and a null
/// [onDismiss] hides the button, which is how a strip shows it only while
/// there is something to clear.
///
/// Key prefixes: none of its own. The caller's `key` sits on the field, so
/// `enterText` and `find.descendant` reach the text through it, and
/// [dismissKey] sits on the button.
///
/// ```dart
/// QuarkSearchField(
///   key: const ValueKey('photos_search_field'),
///   hintText: 'Search photos by name…',
///   onChanged: controller.setSearchQuery,
///   onDismiss: closeSearch,
///   dismissTooltip: 'Close search',
///   dismissKey: const ValueKey('photos_search_close'),
/// );
/// ```
class QuarkSearchField extends StatelessWidget {
  /// Creates a search field reading [hintText] while empty.
  const QuarkSearchField({
    required this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onDismiss,
    this.dismissTooltip = 'Clear search',
    this.dismissKey,
    super.key,
  });

  /// The placeholder, such as "Search files…".
  final String hintText;

  /// The text, when the caller needs to read or clear it. Null lets the
  /// field keep its own.
  final TextEditingController? controller;

  /// The focus, when the caller moves it or listens to it.
  final FocusNode? focusNode;

  /// Whether the field asks for the focus when it first appears.
  final bool autofocus;

  /// Called with the text on every edit.
  final ValueChanged<String>? onChanged;

  /// Called when the close button is pressed. Null hides the button.
  final VoidCallback? onDismiss;

  /// What the close button says on hover and to a screen reader: "Clear
  /// search" when it empties the field, "Close search" when it leaves.
  final String dismissTooltip;

  /// The key on the close button.
  final Key? dismissKey;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: tokens.border),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
        prefixIcon: Icon(
          QuarkIcons.search,
          size: quarkMenuIconSize,
          color: tokens.secondaryForeground,
        ),
        suffixIcon: onDismiss == null
            ? null
            : IconButton(
                key: dismissKey,
                tooltip: dismissTooltip,
                icon: Icon(
                  QuarkIcons.close,
                  size: quarkMenuIconSize,
                  color: tokens.secondaryForeground,
                ),
                onPressed: onDismiss,
              ),
        filled: true,
        fillColor: tokens.input,
        border: border,
        enabledBorder: border,
      ),
    );
  }
}
