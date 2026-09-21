import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// A refresh [IconButton] that swaps its glyph for a spinner while a refresh
/// is in flight, and refuses taps until it finishes.
///
/// Whether a refresh is running is an input, not something the button tracks:
/// the page owns the load.
///
/// Key prefixes: `refresh_button` on the control itself.
///
/// ```dart
/// RefreshIconButton(
///   isRefreshing: controller.isLoading,
///   onPressed: controller.refresh,
/// );
/// ```
class RefreshIconButton extends StatelessWidget {
  /// Creates a refresh button showing a spinner while [isRefreshing].
  const RefreshIconButton({
    required this.onPressed,
    required this.isRefreshing,
    this.tooltip = 'Refresh',
    super.key,
  });

  /// Starts a refresh. Null disables the button outright, for a page that has
  /// nothing to refresh yet.
  final VoidCallback? onPressed;

  /// Whether a refresh is already running. True shows the spinner and blocks
  /// further taps.
  final bool isRefreshing;

  /// The button's tooltip.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    // The theme's icon style, not the ambient one: an AppBar swaps in a larger
    // icon and its own foreground color, which made the app bar's refresh look
    // unlike the one in the file browser's top bar (#2254).
    final iconTheme = Theme.of(context).iconTheme;
    final size = iconTheme.size ?? 20;
    return IconButton(
      key: const ValueKey('refresh_button'),
      tooltip: tooltip,
      iconSize: size,
      color: iconTheme.color,
      onPressed: isRefreshing ? null : onPressed,
      icon: isRefreshing
          ? SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: iconTheme.color,
              ),
            )
          : const Icon(QuarkIcons.refresh),
    );
  }
}
