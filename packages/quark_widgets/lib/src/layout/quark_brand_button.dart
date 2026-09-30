import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// The branded badge-and-label control that leads every main page's top bar.
///
/// It is a button, not a title: tapping it is how the app opens the navigation
/// drawer. When used as [AppBar.leading], set [AppBar.leadingWidth] to at least
/// [QuarkBrandButton.preferredWidth] or the row overflows.
///
/// Key prefixes: `brand_button` on the control itself.
///
/// ```dart
/// QuarkBrandButton(
///   label: 'Files',
///   onTap: () => Scaffold.of(context).openDrawer(),
/// );
/// ```
class QuarkBrandButton extends StatelessWidget {
  /// Creates a brand button labeled [label].
  const QuarkBrandButton({
    required this.label,
    required this.onTap,
    this.icon = QuarkIcons.storage_rounded,
    super.key,
  });

  /// Use this as [AppBar.leadingWidth] when placing this widget in an app bar.
  static const double preferredWidth = 140.0;

  /// The page label shown next to the icon, for example "Files" or "Photos".
  final String label;

  /// Called when the button is tapped. Typically opens the drawer.
  final VoidCallback onTap;

  /// The glyph inside the brand badge. Defaults to
  /// [QuarkIcons.storage_rounded]; pass a page-appropriate icon elsewhere.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusMd);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: InkWell(
          key: const ValueKey('brand_button'),
          onTap: onTap,
          borderRadius: radius,
          // At least 48 tall, so the badge and label answer taps across a
          // full target rather than the 36 pixels they draw (#2605).
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.spacingXs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: radius,
                    ),
                    child: Center(
                      child: Icon(icon, size: 16, color: colorScheme.onPrimary),
                    ),
                  ),
                  SizedBox(width: tokens.spacingSm + tokens.spacingXs / 2),
                  // Flexible, with an ellipsis: the button sits in a bar slot
                  // of a fixed width, so a page name longer than fits has to be
                  // clipped rather than overflow the bar.
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
