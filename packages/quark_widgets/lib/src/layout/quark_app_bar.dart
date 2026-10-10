import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_app_bar_bottom.dart';
import 'quark_app_bar_trailing.dart';
import 'quark_bar_icon_button.dart';
import 'quark_brand_button.dart';
import 'quark_chrome.dart';
import 'quark_handedness.dart';
import 'refresh_icon_button.dart';

/// The app bar every main page wears: a [QuarkBrandButton] on the left that
/// opens the drawer, an optional refresh button beside it, no page title, and
/// the page's own actions on the right, above a hairline.
///
/// Refresh is a slot, not an action. Files has always kept its reload next to
/// the navigation arrows while every other page buried it somewhere in
/// [actions], so the button moved here and the page now hands over
/// [onRefresh] and [isRefreshing] instead of building one. There is no way to
/// put it anywhere else, which is the point.
///
/// Every action is a bar button — a [QuarkBarIconButton], a [QuarkBarChip],
/// or a package widget built on one, such as the theme toggle and the jobs
/// badge — so every page's actions share one shape and one glyph size
/// (#2311). The theme toggle is not built in. It reads the app's settings, so
/// the page appends its own wired copy to [actions] and the package stays
/// free of app state.
///
/// App-wide controls, such as a running-jobs badge, come from a
/// [QuarkAppBarTrailing] scope and follow [actions].
///
/// Under a left-handed [QuarkHandedness] scope the bar is mirrored (#1812):
/// the brand button sits against the right edge with the refresh inside it,
/// and the actions run in from the left. Only the order of the slots flips.
/// What is in a slot, the brand's badge and label or a page's [middle], reads
/// the way it always does.
///
/// [middle] fills the space between the leading slot and the actions, for a
/// page whose bar holds more than buttons (Files' navigation and inline
/// search). [bottom] adds a second row, usually a [QuarkAppBarBottom].
///
/// Key prefixes: `brand_button`, from the [QuarkBrandButton] it renders, and
/// `refresh_button`, from the [RefreshIconButton] it renders when [onRefresh]
/// is set.
///
/// ```dart
/// Scaffold(
///   appBar: QuarkAppBar(
///     label: 'Photos',
///     icon: QuarkIcons.photo_library_outlined,
///     onRefresh: manualRefresh,
///     isRefreshing: isRefreshing,
///     actions: const [AppThemeToggle()],
///   ),
/// );
/// ```
class QuarkAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the shared app bar for a page called [label].
  const QuarkAppBar({
    required this.label,
    required this.icon,
    this.actions = const [],
    this.onRefresh,
    this.isRefreshing = false,
    this.middle,
    this.bottom,
    super.key,
  });

  /// The page name shown in the brand button.
  final String label;

  /// The glyph in the brand badge, usually the page's drawer icon.
  final IconData icon;

  /// Trailing controls, rendered in order at the end of the bar. Any
  /// [QuarkAppBarTrailing] scope above adds its controls after these.
  ///
  /// Never a refresh button — that is [onRefresh].
  final List<Widget> actions;

  /// Reloads the page. Non-null renders the shared [RefreshIconButton] right
  /// after the brand button; null leaves the slot out entirely, which is what
  /// a page with nothing to reload yet passes.
  final VoidCallback? onRefresh;

  /// Whether that reload is already running. Shows the spinner and blocks
  /// further taps. Ignored when [onRefresh] is null.
  final bool isRefreshing;

  /// Fills the bar between the refresh slot and [actions], and is what gives
  /// way first when the bar is narrow. Null leaves that space empty.
  final Widget? middle;

  /// A second row below the bar. Null renders a single row.
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    // The bar is chrome: its own hairline, and everything placed in it.
    final tokens = QuarkTokens.of(context).onChrome;
    final refresh = onRefresh;
    // Left-handed, the bar's rows run the other way, which is the whole
    // mirror. Each slot then puts back the direction the page is read in, so
    // nothing inside a button or a page's middle is laid out backwards.
    final reading = Directionality.of(context);
    final mirrored = reading == TextDirection.ltr
        ? TextDirection.rtl
        : TextDirection.ltr;
    final leftHanded = QuarkHandedness.isLeftHanded(context);
    Widget slot(Widget child) => leftHanded
        ? Directionality(textDirection: reading, child: child)
        : child;
    final trailing = [
      for (final action in [...actions, ...QuarkAppBarTrailing.of(context)])
        slot(action),
    ];
    final middle = this.middle;
    final bottom = this.bottom;
    final slotWidth =
        QuarkBrandButton.preferredWidth +
        (refresh == null ? 0 : QuarkBarIconButton.tapTargetSize);
    // No spacing in the bar's rows: every bar control carries its own
    // margin, the edge of its 48dp touch target (#2605).
    Widget brandAndRefresh(BuildContext ctx) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, so a page name longer than the slot is clipped by the
        // brand button rather than overflowing the bar.
        Flexible(
          child: slot(
            QuarkBrandButton(
              label: label,
              icon: icon,
              // Whichever edge the page hung its drawer on.
              onTap: () {
                final scaffold = Scaffold.of(ctx);
                scaffold.hasEndDrawer
                    ? scaffold.openEndDrawer()
                    : scaffold.openDrawer();
              },
            ),
          ),
        ),
        if (refresh != null)
          slot(
            RefreshIconButton(isRefreshing: isRefreshing, onPressed: refresh),
          ),
      ],
    );
    return QuarkChrome(
      child: Directionality(
        textDirection: leftHanded ? mirrored : reading,
        child: AppBar(
          shape: Border(bottom: BorderSide(color: tokens.border)),
          automaticallyImplyLeading: false,
          // Without a middle, the brand and refresh hold a fixed leading slot,
          // so the brand stays whole however many actions a page has.
          leadingWidth: middle == null ? tokens.spacingSm + slotWidth : null,
          leading: middle == null
              ? Builder(
                  builder: (ctx) => Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: tokens.spacingSm,
                    ),
                    child: brandAndRefresh(ctx),
                  ),
                )
              : null,
          // With one, they share a row with it and take only the width the
          // label needs, which is what leaves Files room for its navigation
          // and search on a phone.
          title: middle == null
              ? null
              : Builder(
                  builder: (ctx) => Row(
                    spacing: tokens.spacingSm,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: slotWidth),
                        child: brandAndRefresh(ctx),
                      ),
                      Expanded(child: slot(middle)),
                    ],
                  ),
                ),
          titleSpacing: tokens.spacingSm,
          centerTitle: false,
          actions: trailing.isEmpty
              ? null
              : [Row(mainAxisSize: MainAxisSize.min, children: trailing)],
          bottom: bottom == null
              ? null
              : PreferredSize(
                  preferredSize: bottom.preferredSize,
                  child: slot(bottom),
                ),
        ),
      ),
    );
  }
}
