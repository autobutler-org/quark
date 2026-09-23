import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_chip.dart';
import 'quark_bar_icon_button.dart';

/// The second row of a [QuarkAppBar]: where the user is on the left, and the
/// page's secondary actions on the right.
///
/// This is where the bar's one breakpoint lives. At [collapseBreakpoint] and
/// wider, [actions] sit in the row. Narrower, they give way to a single chip
/// reading [menuLabel] that opens [menuChildren] — a labeled menu, never an
/// anonymous `⋮`, so a phone user can still tell what is behind it. Files
/// used to make that decision itself with an 860 pixel `LayoutBuilder`; it
/// lives here so every page that needs a second row shares it.
///
/// [menuChildren] is not a copy of [actions]: a chip row and a menu are
/// different shapes, and a page may offer less on a phone (Files' create
/// actions move to a floating button there).
///
/// Key prefixes: `app_bar_bottom_menu` on the chip that opens the menu.
///
/// ```dart
/// QuarkAppBar(
///   label: 'Files',
///   icon: QuarkIcons.folder_outlined,
///   bottom: QuarkAppBarBottom(
///     lead: breadcrumb,
///     actions: [uploadChip, newFolderChip, viewToggle],
///     menuChildren: [layoutItems, groupingItem],
///   ),
/// );
/// ```
class QuarkAppBarBottom extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a second row led by [lead].
  const QuarkAppBarBottom({
    required this.lead,
    this.actions = const [],
    this.menuChildren = const [],
    this.menuLabel = 'Views',
    this.menuIcon = QuarkIcons.tune_rounded,
    super.key,
  });

  /// The row's width below which [actions] collapse into the menu.
  static const double collapseBreakpoint = 860;

  /// The row's height: one bar button and a small gap above and below it.
  static const double height = QuarkBarIconButton.size + 16;

  /// What fills the left of the row, usually a breadcrumb. It is given the
  /// width the actions leave, so it can truncate itself to fit.
  final Widget lead;

  /// The row's actions at [collapseBreakpoint] and wider, in order.
  final List<Widget> actions;

  /// What the menu holds below [collapseBreakpoint]. Empty leaves the menu
  /// out entirely.
  final List<Widget> menuChildren;

  /// The word on the chip that opens the menu.
  final String menuLabel;

  /// The glyph on the chip that opens the menu, from `QuarkIcons`.
  final IconData menuIcon;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border, width: 0.5)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingSm + tokens.spacingXs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < collapseBreakpoint;
          return Row(
            spacing: tokens.spacingSm,
            children: [
              Expanded(child: lead),
              if (!compact) ...actions,
              if (compact && menuChildren.isNotEmpty)
                MenuAnchor(
                  style: MenuStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(220, 0)),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusLg),
                      ),
                    ),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: tokens.spacingSm),
                    ),
                  ),
                  menuChildren: menuChildren,
                  builder: (context, controller, _) => QuarkBarChip(
                    key: const ValueKey('app_bar_bottom_menu'),
                    icon: menuIcon,
                    label: menuLabel,
                    keepLabel: true,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
