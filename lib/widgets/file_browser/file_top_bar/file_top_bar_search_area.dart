import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_search_field.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_select_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The bar's second row while search is open: the field across the whole row,
/// and Select beside it so search results can be selected.
///
/// The field used to open in the top row beside the back button, where on a
/// phone it got a few pixels and could not be typed into (#3454). Here it has
/// the row's width at every size.
class FileTopBarSearchArea extends StatelessWidget
    implements PreferredSizeWidget {
  const FileTopBarSearchArea({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    this.onStartSelection,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// Enters multi-select. Null leaves Select out.
  final VoidCallback? onStartSelection;

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final onStartSelection = this.onStartSelection;
    return QuarkAppBarBottom(
      lead: FileTopBarSearchField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onClose: onClose,
      ),
      pinnedActions: [
        if (onStartSelection != null)
          FileTopBarSelectButton(onPressed: onStartSelection),
      ],
    );
  }
}
