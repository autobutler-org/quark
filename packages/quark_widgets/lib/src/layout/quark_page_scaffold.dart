import 'package:flutter/material.dart';

import 'quark_app_bar.dart';

/// The shape every top-level Quark page wears: the shared app bar, the
/// navigation drawer, a body, and an optional bar pinned to the bottom.
///
/// Pages used to build this `Scaffold` themselves, which is how eight of them
/// ended up with eight slightly different ideas of what a page is. The bar,
/// the drawer slot, and the bottom inset are decided here once.
///
/// The default bar is a [QuarkAppBar] built from [title], [icon], [actions],
/// and the refresh slot ([onRefresh] and [isRefreshing]). A page that swaps
/// its bar out for a mode of its own, a selection bar for instance, passes
/// [appBar] instead, and all of those are then unused.
///
/// [bottomBar] is laid out inside a [SafeArea], so a bar handed to it clears
/// the home indicator without the caller thinking about insets. The body is
/// left alone: its content scrolls under the system bars, which is what a
/// photo grid wants.
///
/// Key prefixes: `brand_button` and `refresh_button`, from the [QuarkAppBar]
/// it builds. The scaffold has nothing tappable of its own.
///
/// ```dart
/// QuarkPageScaffold(
///   title: 'Photos',
///   icon: QuarkIcons.photo_library_outlined,
///   onRefresh: reload,
///   isRefreshing: false,
///   drawer: QuarkDrawer(activeSection: QuarkDrawerSection.photos),
///   bottomBar: PhotoSelectionBar(selectedCount: 3, ...),
///   body: QuarkSplitView(sidebar: sidebar, slivers: slivers),
/// );
/// ```
class QuarkPageScaffold extends StatelessWidget {
  /// Creates the page shell for a page called [title].
  const QuarkPageScaffold({
    required this.title,
    required this.icon,
    required this.body,
    this.actions = const [],
    this.onRefresh,
    this.isRefreshing = false,
    this.drawer,
    this.bottomBar,
    this.appBar,
    super.key,
  });

  /// The page name shown in the app bar's brand button.
  final String title;

  /// The glyph in the brand badge, usually the page's drawer icon.
  final IconData icon;

  /// The page content, filling everything between the bars.
  final Widget body;

  /// Trailing controls for the default app bar, rendered in order. Never a
  /// refresh button — that is [onRefresh].
  final List<Widget> actions;

  /// Reloads the page, rendered by the default app bar beside its brand
  /// button. Null leaves the slot out.
  final VoidCallback? onRefresh;

  /// Whether that reload is already running. Ignored when [onRefresh] is null.
  final bool isRefreshing;

  /// The navigation drawer, opened by the brand button. Null leaves the page
  /// without one, and the brand button then does nothing.
  final Widget? drawer;

  /// A bar pinned below [body] and inset for the system bottom edge. Null
  /// renders no bar and gives the body the full height.
  final Widget? bottomBar;

  /// Replaces the default [QuarkAppBar] entirely, for a page with a second
  /// mode. Null builds the default bar from [title], [icon], [actions], and
  /// the refresh slot.
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          appBar ??
          QuarkAppBar(
            label: title,
            icon: icon,
            actions: actions,
            onRefresh: onRefresh,
            isRefreshing: isRefreshing,
          ),
      drawer: drawer,
      body: body,
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(top: false, child: bottomBar!),
    );
  }
}
