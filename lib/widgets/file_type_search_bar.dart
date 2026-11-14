import 'package:material_ui/material_ui.dart';
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
        builder: (context, _) => QuarkSearchField(
          key: ValueKey('${keyPrefix}_search'),
          controller: controller,
          hintText: hintText,
          onDismiss: controller.text.isEmpty ? null : controller.clear,
          dismissKey: ValueKey('${keyPrefix}_search_clear'),
        ),
      ),
    );
  }
}
