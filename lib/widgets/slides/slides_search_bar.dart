import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The filter strip above the presentations list.
///
/// Key prefixes: `slides_search` on the field, `slides_search_clear` on its
/// clear button.
class SlidesSearchBar extends StatelessWidget {
  /// Filters as [controller]'s text changes.
  const SlidesSearchBar({required this.controller, super.key});

  /// The search text, owned by the page.
  final TextEditingController controller;

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
          key: const ValueKey('slides_search'),
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search presentations…',
            prefixIcon: const Icon(QuarkIcons.search_rounded, size: 20),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('slides_search_clear'),
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
