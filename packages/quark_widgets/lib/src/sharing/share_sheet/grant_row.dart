import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/access_level.dart';
import '../../models/grant_item.dart';
import '../../models/principal_item.dart';
import '../../theme/quark_tokens.dart';

/// One account or group with access in a [ShareSheet]: its name and level,
/// and for access set on the item, a level menu and a remove button.
///
/// An inherited grant is read-only and names the folder it is set on.
///
/// A part of [ShareSheet], tested through it.
///
/// Key prefixes: `share_grant_<kind>_<id>`, `share_level_<kind>_<id>`,
/// `share_level_<kind>_<id>_<level>`, `share_revoke_<kind>_<id>`, and
/// `share_inherited_<kind>_<id>` on an inherited row.
class GrantRow extends StatelessWidget {
  /// Creates the row for [grant].
  const GrantRow({
    required this.grant,
    this.canChange = false,
    this.canGrantOwner = false,
    this.isBusy = false,
    this.onSetLevel,
    this.onRevoke,
    super.key,
  });

  /// The access this row shows.
  final GrantItem grant;

  /// Whether this row's level and access can be changed. Ignored for an
  /// inherited grant, which never can.
  final bool canChange;

  /// Whether the level menu offers the owner level.
  final bool canGrantOwner;

  /// Whether a change to this access is in flight.
  final bool isBusy;

  /// Changes the level. Null disables the menu.
  final ValueChanged<AccessLevel>? onSetLevel;

  /// Removes the access. Null disables the button.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final principal = grant.principal;
    final suffix = principal.keySuffix;
    final name = principal.name;
    final muted = TextStyle(color: tokens.mutedForeground);
    final leading = Icon(
      principal.kind == PrincipalKind.user
          ? QuarkIcons.person_outline
          : Icons.group_outlined,
    );
    final title = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
    final from = grant.inheritedFrom;

    if (from != null) {
      return ListTile(
        key: ValueKey('share_inherited_$suffix'),
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: title,
        subtitle: Text(
          '${grant.level.label} · From $from',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: muted,
        ),
      );
    }

    final setLevel = canChange ? onSetLevel : null;
    final revoke = canChange ? onRevoke : null;

    return ListTile(
      key: ValueKey('share_grant_$suffix'),
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: title,
      subtitle: principal.isBuiltin
          ? Text('Every account', style: muted)
          : null,
      trailing: isBusy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<AccessLevel>(
                  key: ValueKey('share_level_$suffix'),
                  enabled: setLevel != null,
                  tooltip: 'Change access for $name',
                  initialValue: grant.level,
                  onSelected: setLevel,
                  itemBuilder: (context) => [
                    for (final level in AccessLevel.values)
                      if (level != AccessLevel.owner || canGrantOwner)
                        PopupMenuItem(
                          key: ValueKey('share_level_${suffix}_${level.name}'),
                          value: level,
                          child: Text(level.label),
                        ),
                  ],
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacingSm,
                      vertical: tokens.spacingXs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grant.level.label,
                          style: setLevel == null ? muted : null,
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: setLevel == null
                              ? tokens.mutedForeground
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('share_revoke_$suffix'),
                  tooltip: 'Remove access for $name',
                  icon: const Icon(QuarkIcons.close),
                  onPressed: revoke,
                ),
              ],
            ),
    );
  }
}
