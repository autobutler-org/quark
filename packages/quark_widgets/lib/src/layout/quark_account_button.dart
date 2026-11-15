import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';

/// The one app-wide control a phone's app bar carries (#4150): a
/// [QuarkBarIconButton] that opens the account sheet, where the
/// notifications, jobs, connection, theme and the switch to another Quark
/// live.
///
/// It stands in for the connection pill, the jobs badge, the notifications
/// bell and the theme toggle, which do not fit a phone's bar beside the
/// page's own actions. [showDot] hangs a small dot on it when something
/// behind it wants a look; the caller decides what that is.
///
/// Key prefixes: `account_button` on the button.
///
/// ```dart
/// QuarkAccountButton(
///   showDot: unreadCount > 0,
///   onPressed: openAccountSheet,
/// );
/// ```
class QuarkAccountButton extends StatelessWidget {
  /// Creates the account button.
  const QuarkAccountButton({
    required this.onPressed,
    this.showDot = false,
    super.key,
  });

  /// Opens the account sheet.
  final VoidCallback onPressed;

  /// Whether something behind the button wants a look, such as an unread
  /// notification, a running job or a lost connection. Shows a dot and says
  /// so in the tooltip.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return QuarkBarIconButton(
      key: const ValueKey('account_button'),
      icon: QuarkIcons.person_outline,
      tooltip: showDot ? 'Account, something new' : 'Account',
      onPressed: onPressed,
      badge: showDot
          ? Badge(smallSize: 8, backgroundColor: tokens.primary)
          : null,
    );
  }
}
