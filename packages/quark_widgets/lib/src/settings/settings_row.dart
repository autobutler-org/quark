import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// One settings row: a card whose only child is a `ListTile`, or a
/// `SwitchListTile` from [SettingsRow.toggle].
///
/// A tap row reports [onTap] and shows a chevron when it leads somewhere.
/// A [destructive] row paints its icon and title in the theme's error color
/// and should not carry a chevron. A switch row shows [value] and reports
/// the flipped value through [onChanged]; a [flush] switch row drops the
/// card and the tile's side padding, for a switch that already sits inside
/// a section.
///
/// Key prefixes: none of its own. The key the caller passes lands on the
/// row, so `tap #settings_open_storage` reaches it.
///
/// ```dart
/// SettingsRow(
///   key: const ValueKey('settings_open_storage'),
///   leading: const Icon(QuarkIcons.storage),
///   title: const Text('Storage devices'),
///   subtitle: const Text('View, mount and rename drives'),
///   chevron: true,
///   onTap: openStorage,
/// );
/// SettingsRow.toggle(
///   title: const Text('Demo mode'),
///   value: demoMode,
///   onChanged: setDemoMode,
/// );
/// ```
class SettingsRow extends StatelessWidget {
  /// Creates a tap row titled [title].
  const SettingsRow({
    required this.title,
    this.leading,
    this.subtitle,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
    super.key,
  }) : value = null,
       onChanged = null,
       flush = false;

  /// Creates a switch row titled [title], showing [value].
  const SettingsRow.toggle({
    required this.title,
    required bool this.value,
    this.onChanged,
    this.subtitle,
    this.flush = false,
    super.key,
  }) : leading = null,
       onTap = null,
       chevron = false,
       destructive = false;

  /// What the row is, usually a `Text`.
  final Widget title;

  /// Shown before the title, usually an `Icon`; null shows nothing.
  final Widget? leading;

  /// A line under the title; null shows nothing.
  final Widget? subtitle;

  /// Called when a tap row is tapped. Null leaves the row inert.
  final VoidCallback? onTap;

  /// Whether a tap row ends in a chevron, for a row that opens another page.
  final bool chevron;

  /// Whether the row's icon and title wear the error color, for a row that
  /// deletes or resets.
  final bool destructive;

  /// Whether a switch row's switch is on; null on a tap row.
  final bool? value;

  /// Called with the new value when a switch row is flipped. Null disables
  /// the switch.
  final ValueChanged<bool>? onChanged;

  /// Whether a switch row skips the card and the tile's side padding.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final error = Theme.of(context).colorScheme.error;
    final tile = value != null
        ? SwitchListTile(
            contentPadding: flush ? EdgeInsets.zero : null,
            title: title,
            subtitle: subtitle,
            value: value,
            onChanged: onChanged,
          )
        : ListTile(
            iconColor: destructive ? error : null,
            leading: leading,
            title: destructive
                ? DefaultTextStyle.merge(
                    style: TextStyle(color: error),
                    child: title,
                  )
                : title,
            subtitle: subtitle,
            trailing: chevron ? const Icon(QuarkIcons.chevron_right) : null,
            onTap: onTap,
          );
    return flush ? tile : Card(child: tile);
  }
}
