import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_segmented_choice.dart';
import '../theme/quark_tokens.dart';
import 'quark_section.dart';

/// What a phone's account button opens (#4150): the app-wide controls a
/// wide app bar shows one by one, gathered in sections.
///
/// In order: [notifications], the running [runningJobs] with a way to the
/// jobs list, [connection], the theme, and the Quark this app is signed in
/// to with a way to switch. [notifications] and [connection] are whole
/// panels the app builds, the same ones its bell and connection pill open
/// on a wide bar; null leaves that section out.
///
/// The sheet frame is the caller's: show it with `showQuarkSheet`.
///
/// Key prefixes: `account_sheet_jobs` on the jobs row,
/// `account_theme_<mode>` (`system`, `light`, `dark`) on each theme choice,
/// `account_sheet_switch_quark` on the switch row, and `section_<title>`
/// from each [QuarkSection].
///
/// ```dart
/// showQuarkSheet<void>(
///   context,
///   title: 'Account',
///   builder: (sheetContext) => QuarkAccountSheet(
///     notifications: NotificationsList(...),
///     runningJobs: 2,
///     onOpenJobs: openJobs,
///     connection: ConnectionSheet(...),
///     themeMode: ThemeMode.system,
///     onThemeModeChanged: setTheme,
///     quarkName: 'Home',
///     onSwitchQuark: openHosts,
///   ),
/// );
/// ```
class QuarkAccountSheet extends StatelessWidget {
  /// Creates the sheet's sections.
  const QuarkAccountSheet({
    required this.runningJobs,
    required this.onOpenJobs,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.quarkName,
    required this.onSwitchQuark,
    this.notifications,
    this.connection,
    super.key,
  });

  /// The notifications panel. Null leaves the section out, as when nobody
  /// is signed in.
  final Widget? notifications;

  /// How many jobs and uploads are running.
  final int runningJobs;

  /// Opens the jobs list.
  final VoidCallback onOpenJobs;

  /// The connection panel: how the app reaches its Quark and its controls.
  /// Null leaves the section out, as on the web.
  final Widget? connection;

  /// The theme mode in effect.
  final ThemeMode themeMode;

  /// Called with the theme mode the reader picked.
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// The name of the Quark this app is on.
  final String quarkName;

  /// Opens where another Quark is picked or added.
  final VoidCallback onSwitchQuark;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final notifications = this.notifications;
    final connection = this.connection;
    final gap = SizedBox(height: tokens.spacingLg);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notifications != null) ...[
          QuarkSection(title: 'Notifications', child: notifications),
          gap,
        ],
        QuarkSection(
          title: 'Jobs',
          child: ListTile(
            key: const ValueKey('account_sheet_jobs'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(QuarkIcons.pending_actions_outlined),
            title: Text(switch (runningJobs) {
              0 => 'Nothing running',
              1 => '1 running',
              _ => '$runningJobs running',
            }),
            trailing: const Icon(QuarkIcons.chevron_right),
            onTap: onOpenJobs,
          ),
        ),
        gap,
        if (connection != null) ...[
          QuarkSection(title: 'Connection', child: connection),
          gap,
        ],
        QuarkSection(
          title: 'Theme',
          child: QuarkSegmentedChoice<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System', key: ValueKey('account_theme_system')),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light', key: ValueKey('account_theme_light')),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark', key: ValueKey('account_theme_dark')),
              ),
            ],
            selected: themeMode,
            onChanged: onThemeModeChanged,
          ),
        ),
        gap,
        QuarkSection(
          title: 'Quark',
          child: ListTile(
            key: const ValueKey('account_sheet_switch_quark'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(QuarkIcons.storage),
            title: Text(
              quarkName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('Switch Quark'),
            trailing: const Icon(QuarkIcons.chevron_right),
            onTap: onSwitchQuark,
          ),
        ),
      ],
    );
  }
}
