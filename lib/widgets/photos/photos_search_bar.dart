import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The strip under the Photos bar that takes a search by file name (#2059).
///
/// It holds no query of its own beyond the text being typed: every change
/// goes out through [onChanged], and the button at its end asks to leave the
/// search through [onClose]. The field takes the focus as it appears, since
/// opening it is asking to type.
///
/// Keys: `photos_search_field` on the text field and `photos_search_close`
/// on the button that ends the search.
///
/// ```dart
/// PhotosSearchBar(
///   onChanged: controller.setSearchQuery,
///   onClose: closeSearch,
/// );
/// ```
class PhotosSearchBar extends StatelessWidget {
  /// Creates the strip.
  const PhotosSearchBar({
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  /// Called with the text on every edit.
  final ValueChanged<String> onChanged;

  /// Called when the search is closed.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: tokens.border),
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.chrome,
        border: Border(bottom: BorderSide(color: tokens.chromeBorder)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingLg,
        vertical: tokens.spacingSm,
      ),
      child: TextField(
        key: const ValueKey('photos_search_field'),
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search photos by name…',
          prefixIcon: const Icon(QuarkIcons.search_rounded, size: 20),
          suffixIcon: IconButton(
            key: const ValueKey('photos_search_close'),
            tooltip: 'Close search',
            icon: const Icon(QuarkIcons.close_rounded, size: 18),
            onPressed: onClose,
          ),
          isDense: true,
          filled: true,
          fillColor: tokens.input,
          border: border,
          enabledBorder: border,
        ),
      ),
    );
  }
}
