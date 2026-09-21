import 'package:flutter/material.dart';

import 'quark_app_bar_trailing.dart';
import 'quark_brand_button.dart';
import 'refresh_icon_button.dart';

/// The app bar every main page wears: a [QuarkBrandButton] on the left that
/// opens the drawer, an optional refresh button beside it, no title, and the
/// page's own actions on the right.
///
/// Refresh is a slot, not an action. Files has always kept its reload next to
/// the navigation arrows while every other page buried it somewhere in
/// [actions], so the button moved here and the page now hands over
/// [onRefresh] and [isRefreshing] instead of building one. There is no way to
/// put it anywhere else, which is the point.
///
/// The theme toggle is not built in. It reads the app's settings, so the page
/// appends its own wired copy to [actions] and the package stays free of app
/// state.
///
/// App-wide controls, such as a running-jobs badge, come from a
/// [QuarkAppBarTrailing] scope and follow [actions].
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
    super.key,
  });

  /// The gap between the brand button and what follows it, matching the one
  /// the file browser's top bar leaves.
  static const double _brandGap = 16;

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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    return AppBar(
      leadingWidth:
          QuarkBrandButton.preferredWidth +
          8 +
          (refresh == null ? 0 : _brandGap + kMinInteractiveDimension),
      leading: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible, so a page name longer than the slot is clipped by
              // the brand button rather than overflowing the bar.
              Flexible(
                child: QuarkBrandButton(
                  label: label,
                  icon: icon,
                  onTap: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              if (refresh != null) ...[
                const SizedBox(width: _brandGap),
                RefreshIconButton(
                  isRefreshing: isRefreshing,
                  onPressed: refresh,
                ),
              ],
            ],
          ),
        ),
      ),
      title: null,
      actions: [...actions, ...QuarkAppBarTrailing.of(context)],
    );
  }
}
