import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The page Docs, Sheets and Slides share (#4105): a drawer page whose bar
/// holds the refresh slot, one create chip and the theme toggle, with a
/// [FileTypeSearchBar] over [child], the listing.
///
/// Data in, callbacks out: the page that uses it owns the controller, the
/// search text, the refresh state and the routes.
///
/// Key prefixes: `<keyPrefix>_new` on the create chip, and the search bar's
/// `<keyPrefix>_search` and `<keyPrefix>_search_clear`.
///
/// ```dart
/// FileLibraryPage(
///   title: 'Docs',
///   icon: QuarkIcons.description_outlined,
///   drawerSection: QuarkDrawerSection.docs,
///   keyPrefix: 'docs',
///   createLabel: 'New document',
///   onCreate: _create,
///   searchController: _search,
///   searchHint: 'Search docs…',
///   onRefresh: manualRefresh,
///   isRefreshing: isRefreshing,
///   child: listing,
/// )
/// ```
class FileLibraryPage extends StatelessWidget {
  /// Lays out a library page around [child].
  const FileLibraryPage({
    required this.title,
    required this.icon,
    required this.drawerSection,
    required this.keyPrefix,
    required this.createLabel,
    required this.onCreate,
    required this.searchController,
    required this.searchHint,
    required this.onRefresh,
    required this.isRefreshing,
    required this.child,
    this.createTooltip,
    this.bottom,
    super.key,
  });

  /// The bar's label, such as "Docs".
  final String title;

  /// The glyph beside [title].
  final IconData icon;

  /// The drawer row marked as this page.
  final QuarkDrawerSection drawerSection;

  /// Starts the chip's and the search bar's keys: `docs`, `sheets` or
  /// `slides`.
  final String keyPrefix;

  /// The create chip's label, such as "New document".
  final String createLabel;

  /// The create chip's tooltip; null shows none, the label already says it.
  final String? createTooltip;

  /// Called when the create chip is tapped.
  final VoidCallback onCreate;

  /// The search text, owned by the page.
  final TextEditingController searchController;

  /// The search placeholder, such as "Search docs…".
  final String searchHint;

  /// The bar's refresh slot.
  final VoidCallback onRefresh;

  /// Whether a refresh is running, which spins the refresh button.
  final bool isRefreshing;

  /// A row under the bar, such as Slides' import row; null for none.
  final PreferredSizeWidget? bottom;

  /// The listing under the search bar, given the remaining height.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: title,
      icon: icon,
      appBar: QuarkAppBar(
        label: title,
        icon: icon,
        onRefresh: onRefresh,
        isRefreshing: isRefreshing,
        actions: [
          QuarkBarChip(
            key: ValueKey('${keyPrefix}_new'),
            icon: QuarkIcons.add,
            label: createLabel,
            tooltip: createTooltip,
            onPressed: onCreate,
          ),
          const AppThemeToggle(),
        ],
        bottom: bottom,
      ),
      drawer: AppDrawer(activeSection: drawerSection),
      body: Column(
        children: [
          FileTypeSearchBar(
            controller: searchController,
            hintText: searchHint,
            keyPrefix: keyPrefix,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
