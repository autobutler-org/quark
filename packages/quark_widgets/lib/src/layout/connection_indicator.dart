import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/connection_mode.dart';
import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';

/// A top bar tile saying whether the app reaches its Quark on the home
/// network, through remote access, or not at all.
///
/// It has the shape and size of a [QuarkBarIconButton] so it sits in a bar
/// beside the other actions. The glyph's color carries the state at a glance
/// (success for local, primary for remote, warning for offline), and the
/// caller's [label] says it in words, as the tooltip and the semantics label.
/// With [onTap] it is also a button, which the app uses to open a sheet
/// spelling the connection out; without one it is a plain status.
///
/// Key prefixes: `connection_indicator` on the tile.
///
/// ```dart
/// ConnectionIndicator(
///   mode: ConnectionMode.remote,
///   label: 'Connected through remote access',
///   onTap: openConnectionSheet,
/// );
/// ```
class ConnectionIndicator extends StatelessWidget {
  /// Creates a tile showing [mode], described by [label].
  const ConnectionIndicator({
    required this.mode,
    required this.label,
    this.onTap,
    super.key,
  });

  /// The connection to show.
  final ConnectionMode mode;

  /// What [mode] means, in the caller's words. Shown on hover and read by
  /// screen readers.
  final String label;

  /// Called when the tile is tapped. Null leaves it a plain status.
  final VoidCallback? onTap;

  /// The glyph and its color for [mode], shared with `ConnectionStatusView`
  /// so the sheet shows the same mark the bar does.
  static (IconData, Color) glyphFor(
    ConnectionMode mode,
    QuarkTokens tokens,
  ) => switch (mode) {
    ConnectionMode.local => (QuarkIcons.home_rounded, tokens.success),
    ConnectionMode.remote => (QuarkIcons.cloud_done_outlined, tokens.primary),
    ConnectionMode.offline => (QuarkIcons.cloud_off_outlined, tokens.warning),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (icon, color) = glyphFor(mode, tokens);
    final radius = BorderRadius.circular(tokens.radiusMd);
    final glyph = Icon(icon, size: QuarkBarIconButton.glyphSize, color: color);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: onTap != null,
        onTap: onTap,
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('connection_indicator'),
          width: QuarkBarIconButton.size,
          height: QuarkBarIconButton.size,
          // The margin every bar control keeps, so the indicator sits as far
          // from its neighbors as two bar buttons do.
          margin: const EdgeInsets.all(QuarkBarIconButton.tapTargetMargin),
          decoration: BoxDecoration(
            color: tokens.input,
            border: Border.all(color: tokens.border),
            borderRadius: radius,
          ),
          child: onTap == null
              ? glyph
              : Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: onTap,
                    child: glyph,
                  ),
                ),
        ),
      ),
    );
  }
}
