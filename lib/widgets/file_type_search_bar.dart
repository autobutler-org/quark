import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The filter strip above the Docs, Sheets and Slides lists.
///
/// Key prefixes: `<keyPrefix>_search` on the field and
/// `<keyPrefix>_search_clear` on its clear button, so `slides_search`,
/// `docs_search` and `sheets_search`.
class FileTypeSearchBar extends StatelessWidget {
  /// Filters as [controller]'s text changes.
  const FileTypeSearchBar({
    required this.controller,
    required this.hintText,
    required this.keyPrefix,
    super.key,
  });

  /// The search text, owned by the page.
  final TextEditingController controller;

  /// The placeholder, such as "Search docs…".
  final String hintText;

  /// Starts the field's keys: `slides`, `docs` or `sheets`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(color: tokens.border),
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          key: ValueKey('${keyPrefix}_search'),
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(QuarkIcons.search_rounded, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    key: ValueKey('${keyPrefix}_search_clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(QuarkIcons.clear_rounded, size: 18),
                    onPressed: controller.clear,
                  ),
            isDense: true,
            filled: true,
            fillColor: tokens.input,
            border: border,
            enabledBorder: border,
          ),
        ),
      ),
    );
  }
}
