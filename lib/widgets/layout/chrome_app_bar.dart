import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The app bar of a drill-down page (an editor, a viewer, a detail page): a
/// Material [AppBar] marked as chrome.
///
/// The theme already paints every [AppBar] in `QuarkTokens.chrome` and its
/// title in the chrome's text color. What a bare one misses is [QuarkChrome]:
/// without it a bar button, or any widget reading `QuarkTokens.of(context)`,
/// draws in the content's colors on a surface that is no longer the
/// content's (#2740). A drawer page uses [QuarkAppBar], which wraps itself.
///
/// The page builds [title] and [actions] in its own context, above the
/// [QuarkChrome], so a color it picks for them itself comes from
/// `QuarkTokens.of(context).onChrome`.
class ChromeAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a drill-down page's app bar.
  const ChromeAppBar({this.leading, this.title, this.actions, super.key});

  /// Replaces the implied back button, as [AppBar.leading] does.
  final Widget? leading;

  /// The page's name, as [AppBar.title].
  final Widget? title;

  /// The bar's buttons, as [AppBar.actions].
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return QuarkChrome(
      child: AppBar(leading: leading, title: title, actions: actions),
    );
  }
}
