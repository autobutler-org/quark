import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_nav_buttons.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_search_area.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_icon_button.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The always-visible upper half of the file browser's top bar: brand,
/// navigation, search, the select control and the theme toggle.
class FileTopBarRow extends StatelessWidget {
  const FileTopBarRow({
    required this.currentPath,
    required this.rootPath,
    required this.navEnabled,
    required this.isRefreshing,
    required this.searchExpanded,
    required this.searchController,
    required this.searchFocusNode,
    required this.onGoUp,
    required this.onRefresh,
    required this.onOpenSearch,
    required this.onSearchChanged,
    required this.onCloseSearch,
    required this.onOpenDrawer,
    this.onStartSelection,
    super.key,
  });

  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root.
  final String rootPath;
  final bool navEnabled;
  final bool isRefreshing;
  final bool searchExpanded;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onGoUp;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCloseSearch;
  final VoidCallback onOpenDrawer;

  /// Enters multi-select. Null hides the control.
  ///
  /// Selecting used to be a long press on a row, a gesture a mouse does not
  /// make, so on the web the whole feature was invisible and Files looked like
  /// it had no bulk actions at all (#2057). This button is the only way in now
  /// that a long press opens the row's menu instead (#2245).
  final VoidCallback? onStartSelection;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            QuarkBrandButton(label: 'Files', onTap: onOpenDrawer),
            const SizedBox(width: 16),
            FileTopBarNavButtons(
              navEnabled: navEnabled,
              currentPath: currentPath,
              rootPath: rootPath,
              isRefreshing: isRefreshing,
              onGoUp: onGoUp,
              onRefresh: onRefresh,
            ),
            const SizedBox(width: 8),
            // Middle area: expands to hold the search field when active,
            // otherwise invisible (Spacer equivalent).
            Expanded(
              child: FileTopBarSearchArea(
                expanded: searchExpanded,
                controller: searchController,
                focusNode: searchFocusNode,
                onOpen: onOpenSearch,
                onChanged: onSearchChanged,
                onClose: onCloseSearch,
              ),
            ),
            const SizedBox(width: 4),
            if (onStartSelection != null)
              TopBarIconButton(
                key: const ValueKey('file_top_bar_select'),
                icon: QuarkIcons.check_circle_outline,
                onTap: onStartSelection!,
                tooltip: 'Select files',
              ),
            const AppThemeToggle(),
            ...QuarkAppBarTrailing.of(context),
          ],
        ),
      ),
    );
  }
}
