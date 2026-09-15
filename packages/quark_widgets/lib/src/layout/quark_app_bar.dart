import 'package:flutter/material.dart';

import 'quark_app_bar_trailing.dart';
import 'quark_brand_button.dart';

/// The app bar every main page wears: a [QuarkBrandButton] on the left that
/// opens the drawer, no title, and the page's own actions on the right.
///
/// The theme toggle is not built in. It reads the app's settings, so the page
/// appends its own wired copy to [actions] and the package stays free of app
/// state.
///
/// App-wide controls, such as a running-jobs badge, come from a
/// [QuarkAppBarTrailing] scope and follow [actions].
///
/// Key prefixes: `brand_button`, from the [QuarkBrandButton] it renders.
///
/// ```dart
/// Scaffold(
///   appBar: QuarkAppBar(
///     label: 'Photos',
///     icon: QuarkIcons.photo_library_outlined,
///     actions: [RefreshIconButton(...), const AppThemeToggle()],
///   ),
/// );
/// ```
class QuarkAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the shared app bar for a page called [label].
  const QuarkAppBar({
    required this.label,
    required this.icon,
    this.actions = const [],
    super.key,
  });

  /// The page name shown in the brand button.
  final String label;

  /// The glyph in the brand badge, usually the page's drawer icon.
  final IconData icon;

  /// Trailing controls, rendered in order at the end of the bar. Any
  /// [QuarkAppBarTrailing] scope above adds its controls after these.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leadingWidth: QuarkBrandButton.preferredWidth + 8,
      leading: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: QuarkBrandButton(
            label: label,
            icon: icon,
            onTap: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      title: null,
      actions: [...actions, ...QuarkAppBarTrailing.of(context)],
    );
  }
}
