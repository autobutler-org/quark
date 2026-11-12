import 'package:material_ui/material_ui.dart';

import 'quark_tokens.dart';

/// The dark token set as static constants, kept so existing call sites keep
/// compiling while widgets move into this package.
///
/// Prefer `QuarkTokens.of(context)`. These values are the dark theme's, so a
/// widget reading them ignores the current theme — which is exactly the bug the
/// gallery's theme panel is built to surface. Every reference here is a widget
/// still waiting to be converted.
abstract final class QuarkColors {
  /// See [QuarkTokens.background].
  static final Color background = QuarkTokens.dark.background;

  /// See [QuarkTokens.card].
  static final Color card = QuarkTokens.dark.card;

  /// See [QuarkTokens.sidebar].
  static final Color sidebar = QuarkTokens.dark.sidebar;

  /// See [QuarkTokens.border].
  static final Color border = QuarkTokens.dark.border;

  /// See [QuarkTokens.input].
  static final Color input = QuarkTokens.dark.input;

  /// See [QuarkTokens.mutedForeground].
  static final Color mutedForeground = QuarkTokens.dark.mutedForeground;

  /// See [QuarkTokens.secondaryForeground].
  static final Color secondaryForeground = QuarkTokens.dark.secondaryForeground;

  /// See [QuarkTokens.foreground].
  static final Color foreground = QuarkTokens.dark.foreground;

  /// See [QuarkTokens.cardForeground].
  static final Color cardForeground = QuarkTokens.dark.cardForeground;

  /// See [QuarkTokens.primary].
  static final Color primary = QuarkTokens.dark.primary;

  /// See [QuarkTokens.primaryForeground].
  static final Color primaryForeground = QuarkTokens.dark.primaryForeground;

  /// See [QuarkTokens.error].
  static final Color error = QuarkTokens.dark.error;

  /// See [QuarkTokens.errorForeground].
  static final Color errorForeground = QuarkTokens.dark.errorForeground;

  /// See [QuarkTokens.warning].
  static final Color warning = QuarkTokens.dark.warning;

  /// See [QuarkTokens.success].
  static final Color success = QuarkTokens.dark.success;

  /// See [QuarkTokens.radiusSm].
  static final double radiusSm = QuarkTokens.dark.radiusSm;

  /// See [QuarkTokens.radiusMd].
  static final double radiusMd = QuarkTokens.dark.radiusMd;

  /// See [QuarkTokens.radiusLg].
  static final double radiusLg = QuarkTokens.dark.radiusLg;
}
