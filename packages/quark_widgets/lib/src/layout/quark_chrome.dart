import 'package:flutter/widgets.dart';

/// Marks [child] as sitting on the chrome: the app bar, the drawer, or any
/// other surface painted in `QuarkTokens.chrome`.
///
/// Under it `QuarkTokens.of` returns `QuarkTokens.onChrome`, so text, icons
/// and hairlines come out in the chrome's colors without the widget drawing
/// them knowing where it is. A bar button is the same widget in a card and in
/// the app bar. `QuarkAppBar` and `QuarkDrawer` already wrap themselves; wrap
/// a bar of your own that is painted in the chrome color.
///
/// It is not a theme, so a menu or dialog opened from the chrome is not under
/// it and keeps the content's colors. It paints nothing and has no keys.
///
/// ```dart
/// QuarkChrome(
///   child: ColoredBox(
///     color: QuarkTokens.of(context).chrome,
///     child: QuarkBarIconButton(
///       icon: QuarkIcons.search,
///       tooltip: 'Search',
///       onPressed: controller.openSearch,
///     ),
///   ),
/// );
/// ```
class QuarkChrome extends InheritedWidget {
  /// Marks [child] as sitting on the chrome.
  const QuarkChrome({required super.child, super.key});

  /// Whether [context] is under a [QuarkChrome].
  static bool isOn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QuarkChrome>() != null;

  @override
  bool updateShouldNotify(QuarkChrome oldWidget) => false;
}
