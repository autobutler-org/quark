import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import 'quark_bar_icon_button.dart';

/// A refresh [QuarkBarIconButton] that swaps its glyph for a spinner while a
/// refresh is in flight, and refuses taps until it finishes.
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
    return QuarkBarIconButton(
      key: const ValueKey('refresh_button'),
      icon: QuarkIcons.refresh,
      tooltip: tooltip,
      isBusy: isRefreshing,
      onPressed: onPressed,
    );
  }
}
