import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The page Docs, Sheets and Slides share (#4105): a drawer page whose bar
/// holds the refresh slot and one create chip, with a
/// [FileTypeSearchBar] over [child], the listing.
///
/// A phone, below [QuarkAppBar.compactBreakpoint], gets Files' layout
/// instead (#4227): the bar is the brand and the account button, the create
/// chip and [bottom] give way to a [QuarkCreateFab] that fades while the
/// listing scrolls down, and the search field sits right under the bar.
///
/// Data in, callbacks out: the page that uses it owns the controller, the
/// search text, the refresh state and the routes.
///
/// Key prefixes: `<keyPrefix>_new` on the create chip,
/// `<keyPrefix>_create_fab` on the phone's + button, and the search bar's
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
class FileLibraryPage extends StatefulWidget {
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
    this.onPhoneCreate,
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

  /// Called when the create chip, or a phone's + button, is tapped.
  final VoidCallback onCreate;

  /// What a phone's + button does instead of [onCreate], such as Slides'
  /// sheet that also offers the import [bottom] holds on a wide screen.
  final VoidCallback? onPhoneCreate;

  /// The search text, owned by the page.
  final TextEditingController searchController;

  /// The search placeholder, such as "Search docs…".
  final String searchHint;

  /// Reloads the listing: the bar's refresh slot, and a pull on the
  /// listing, which is a phone's only way to it (#4150).
  final Future<void> Function() onRefresh;

  /// Whether a refresh is running, which spins the refresh button.
  final bool isRefreshing;

  /// A row under the bar, such as Slides' import row; null for none. A
  /// phone leaves it out, so its actions belong in [onPhoneCreate] too.
  final PreferredSizeWidget? bottom;

  /// The listing under the search bar, given the remaining height.
  final Widget child;

  @override
  State<FileLibraryPage> createState() => _FileLibraryPageState();
}

class _FileLibraryPageState extends State<FileLibraryPage> {
  bool _fabVisible = true;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final visible = QuarkCreateFab.visibleAfterScroll(
      offset: n.metrics.pixels,
      delta: n.scrollDelta ?? 0,
      visible: _fabVisible,
    );
    if (visible != _fabVisible) setState(() => _fabVisible = visible);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final phone = QuarkAppBar.isCompact(context);
    return QuarkPageScaffold(
      title: widget.title,
      icon: widget.icon,
      appBar: QuarkAppBar(
        label: widget.title,
        icon: widget.icon,
        onRefresh: widget.onRefresh,
        isRefreshing: widget.isRefreshing,
        actions: [
          if (!phone)
            QuarkBarChip(
              key: ValueKey('${widget.keyPrefix}_new'),
              icon: QuarkIcons.add,
              label: widget.createLabel,
              tooltip: widget.createTooltip,
              onPressed: widget.onCreate,
            ),
        ],
        bottom: phone ? null : widget.bottom,
      ),
      drawer: AppDrawer(activeSection: widget.drawerSection),
      floatingActionButton: phone
          ? QuarkCreateFab(
              key: ValueKey('${widget.keyPrefix}_create_fab'),
              tooltip: widget.createLabel,
              visible: _fabVisible,
              onPressed: widget.onPhoneCreate ?? widget.onCreate,
            )
          : null,
      body: Column(
        children: [
          FileTypeSearchBar(
            controller: widget.searchController,
            hintText: widget.searchHint,
            keyPrefix: widget.keyPrefix,
          ),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
