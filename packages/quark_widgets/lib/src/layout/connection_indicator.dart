import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/connection_mode.dart';
import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';

/// A top bar tile saying whether the app reaches its Quark on the home
/// network, through remote access, or not at all.
///
/// It is a status, not an action: it has the shape and size of a
/// [QuarkBarIconButton] so it sits in a bar beside the other actions, but it
/// takes no taps. The glyph's color carries the state at a glance (success
/// for local, primary for remote, warning for offline), and the caller's
/// [label] says it in words, as the tooltip and the semantics label.
///
/// Key prefixes: `connection_indicator` on the tile.
///
/// ```dart
/// ConnectionIndicator(
///   mode: ConnectionMode.remote,
///   label: 'Connected through remote access',
/// );
/// ```
class ConnectionIndicator extends StatelessWidget {
  /// Creates a tile showing [mode], described by [label].
  const ConnectionIndicator({
    required this.mode,
    required this.label,
    super.key,
  });

  /// The connection to show.
  final ConnectionMode mode;

  /// What [mode] means, in the caller's words. Shown on hover and read by
  /// screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final (icon, color) = switch (mode) {
      ConnectionMode.local => (QuarkIcons.home_rounded, tokens.success),
      ConnectionMode.remote => (QuarkIcons.cloud_done_outlined, tokens.primary),
      ConnectionMode.offline => (QuarkIcons.cloud_off_outlined, tokens.warning),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('connection_indicator'),
          width: QuarkBarIconButton.size,
          height: QuarkBarIconButton.size,
          decoration: BoxDecoration(
            color: tokens.input,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
          child: Icon(icon, size: QuarkBarIconButton.glyphSize, color: color),
        ),
      ),
    );
  }
}
