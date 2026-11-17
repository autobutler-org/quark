import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_resizable_pane.dart';

/// A sidebar beside a scrolling content pane on a wide window, and the same
/// sidebar stacked above that content on a narrow one.
///
/// This is the one place the sidebar breakpoint is written down. Above
/// [collapseBreakpoint] the sidebar is a [QuarkResizablePane] of
/// [sidebarWidth] on the leading edge, with a drag handle between it and the
/// content. Below it the pane
/// would leave the content a sliver of screen, so the sidebar collapses into
/// the top of the content's own scroll view: scroll up and it is there, scroll
/// down and the content has the whole viewport.
///
/// The content is a sliver list rather than a widget so both layouts share one
/// scroll view, which is what lets the collapsed sidebar scroll away with the
/// content instead of stealing height from it. Handing a sliver an unbounded
/// height is also what made the photos view render nothing under 900px, so the
/// collapsed sidebar is shrink-wrapped here and never given an [Expanded]
/// (#1599).
///
/// Whether the collapsed sidebar is showing is the caller's state:
/// [isSidebarOpen] in, [onToggleSidebar] out. The widget holds no state of its
/// own, and a caller that would rather present the sidebar as a drawer or a
/// sheet passes `isSidebarOpen: false` and shows its own.
///
/// The wide pane's width and collapsed flag are the caller's as well
/// (#4294): [sidebarWidth] and [isSidebarCollapsed] in,
/// [onSidebarWidthChanged] and [onSidebarCollapsedChanged] out. With the
/// collapse callback supplied, the wide layout shows the same show/hide
/// button at the top of the content, which is how a collapsed sidebar comes
/// back. [contentWidthOf] takes both values, so a caller sizing its content
/// follows the drag.
///
/// Key prefixes:
/// - `split_view_sidebar` for the sidebar pane, in either layout
/// - `split_view_toggle` for the show/hide button, rendered in the collapsed
///   layout when [onToggleSidebar] is supplied and in the wide one when
///   [onSidebarCollapsedChanged] is
/// - [QuarkResizablePane]'s keys with the id `split_view` on the wide pane
///   and its handle
///
/// ```dart
/// QuarkSplitView(
///   sidebar: AlbumSidebar(selectedAlbumId: albumId),
///   controller: scrollController,
///   slivers: [SliverGrid(...)],
/// );
/// ```
class QuarkSplitView extends StatelessWidget {
  /// Creates a split view of [sidebar] and [slivers].
  const QuarkSplitView({
    required this.sidebar,
    required this.slivers,
    this.controller,
    this.physics,
    this.sidebarWidth = defaultSidebarWidth,
    this.isSidebarOpen = true,
    this.onToggleSidebar,
    this.collapsedSidebarKey,
    this.isSidebarCollapsed = false,
    this.onSidebarWidthChanged,
    this.onSidebarCollapsedChanged,
    super.key,
  });

  /// The window width at or above which the sidebar is a pane of its own.
  ///
  /// Measured against the window rather than this widget's own constraints, so
  /// every page in the app collapses at the same width no matter what it is
  /// nested in.
  static const double collapseBreakpoint = 900;

  /// The width of the sidebar pane in the wide layout.
  static const double defaultSidebarWidth = 280;

  /// The hairline between the sidebar and the content in the collapsed
  /// layout.
  static const double dividerWidth = 1;

  /// Whether a [QuarkSplitView] built under [context] collapses its sidebar.
  ///
  /// For a caller that has to know the layout it is in for a reason other than
  /// layout, such as scheduling work only the collapsed layout needs. A caller
  /// that only wants a different arrangement should hand this widget different
  /// children instead.
  static bool isCollapsed(BuildContext context) =>
      MediaQuery.sizeOf(context).width < collapseBreakpoint;

  /// How wide the content pane of a full-width [QuarkSplitView] is under
  /// [context], the sidebar (unless [isSidebarCollapsed]) and its handle
  /// taken off in the wide layout.
  ///
  /// The number a caller needs to decide how many columns of its own content
  /// fit. Pass the same [sidebarWidth] and [isSidebarCollapsed] the split view
  /// gets. Only meaningful for a split view that fills the window.
  static double contentWidthOf(
    BuildContext context, {
    double sidebarWidth = defaultSidebarWidth,
    bool isSidebarCollapsed = false,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (isCollapsed(context)) return width;
    final pane = isSidebarCollapsed
        ? 0
        : QuarkResizablePane.widthIn(context, width: sidebarWidth);
    return (width - pane - QuarkResizablePane.handleWidth).clamp(
      1.0,
      double.infinity,
    );
  }

  /// The sidebar, rendered as a pane when wide and stacked above the content
  /// when collapsed. It must shrink-wrap its height: the collapsed layout puts
  /// it in a sliver, where an [Expanded] is a hard layout error (#1599).
  final Widget sidebar;

  /// The content, as slivers, so both layouts can share one scroll view.
  final List<Widget> slivers;

  /// The controller for the content's scroll view, shared by both layouts.
  final ScrollController? controller;

  /// The scroll physics for the content's scroll view.
  final ScrollPhysics? physics;

  /// The width of the sidebar pane in the wide layout, clamped by
  /// [QuarkResizablePane.widthIn].
  final double sidebarWidth;

  /// Whether the collapsed sidebar is showing. Ignored in the wide layout,
  /// where the sidebar is always a pane.
  final bool isSidebarOpen;

  /// Fires when the show/hide button is tapped, with the caller expected to
  /// flip [isSidebarOpen]. Null renders no button, for a page whose collapsed
  /// sidebar is reached by scrolling rather than by tapping.
  final VoidCallback? onToggleSidebar;

  /// Attached to the collapsed sidebar's box, for a caller that has to measure
  /// it. Unused in the wide layout.
  final Key? collapsedSidebarKey;

  /// Whether the wide layout's sidebar is collapsed to its handle. Ignored
  /// in the collapsed layout.
  final bool isSidebarCollapsed;

  /// Fires with the wide sidebar's new width as its handle is dragged. Null
  /// keeps it at [sidebarWidth].
  final ValueChanged<double>? onSidebarWidthChanged;

  /// Fires when the wide sidebar is collapsed or reopened, by its handle or
  /// the show/hide button. Null leaves the button out of the wide layout and
  /// keeps the sidebar open.
  final ValueChanged<bool>? onSidebarCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final wide = !isCollapsed(context);
    final onSidebarCollapsedChanged = this.onSidebarCollapsedChanged;
    final showing = wide ? !isSidebarCollapsed : isSidebarOpen;
    final onToggle = !wide
        ? onToggleSidebar
        : onSidebarCollapsedChanged == null
        ? null
        : () => onSidebarCollapsedChanged(!isSidebarCollapsed);
    final toggle = onToggle == null
        ? null
        : SliverToBoxAdapter(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                key: const ValueKey('split_view_toggle'),
                icon: Icon(showing ? QuarkIcons.menu_open : QuarkIcons.menu),
                tooltip: showing ? 'Hide sidebar' : 'Show sidebar',
                onPressed: onToggle,
              ),
            ),
          );

    if (wide) {
      return Row(
        children: [
          QuarkResizablePane(
            id: 'split_view',
            semanticLabel: 'Resize sidebar',
            width: sidebarWidth,
            defaultWidth: defaultSidebarWidth,
            isCollapsed: isSidebarCollapsed,
            onWidthChanged: onSidebarWidthChanged,
            onCollapsedChanged: onSidebarCollapsedChanged,
            child: KeyedSubtree(
              key: const ValueKey('split_view_sidebar'),
              child: sidebar,
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: controller,
              physics: physics,
              slivers: [?toggle, ...slivers],
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        ?toggle,
        if (isSidebarOpen)
          SliverToBoxAdapter(
            child: Column(
              key: collapsedSidebarKey,
              mainAxisSize: MainAxisSize.min,
              // Stretched so the collapsed sidebar spans the viewport the way
              // the pane fills its width, rather than shrinking to its widest
              // child.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: const ValueKey('split_view_sidebar'),
                  child: sidebar,
                ),
                Divider(height: dividerWidth, color: tokens.border),
              ],
            ),
          ),
        ...slivers,
      ],
    );
  }
}
