import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The strip under the Photos bar that takes a search by file name (#2059).
///
/// It holds no query of its own beyond the text being typed: every change
/// goes out through [onChanged], and the button at its end asks to leave the
/// search through [onClose]. The field takes the focus as it appears, since
/// opening it is asking to type. `autofocus` alone is not enough: it does
/// nothing while anything else in the scope has the focus, which the Photos
/// page always does, so the first keys typed went nowhere (#3363). The field
/// asks for the focus outright once its first frame is laid out.
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
class PhotosSearchBar extends StatefulWidget {
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
  State<PhotosSearchBar> createState() => _PhotosSearchBarState();
}

class _PhotosSearchBarState extends State<PhotosSearchBar> {
  final _focusNode = FocusNode(debugLabel: 'photos_search_field');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
        focusNode: _focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: 'Search photos by name…',
          prefixIcon: const Icon(QuarkIcons.search_rounded, size: 20),
          suffixIcon: IconButton(
            key: const ValueKey('photos_search_close'),
            tooltip: 'Close search',
            icon: const Icon(QuarkIcons.close_rounded, size: 18),
            onPressed: widget.onClose,
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
