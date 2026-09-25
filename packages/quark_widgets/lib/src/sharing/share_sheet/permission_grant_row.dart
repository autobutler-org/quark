import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../chat/quark_chat_permission_picker.dart';
import '../../core/quark_loader.dart';
import '../../models/chat_permission.dart';
import '../../models/chat_permission_preset.dart';
import '../../models/grant_item.dart';
import '../../models/principal_item.dart';
import '../../theme/quark_tokens.dart';

/// One member of a chat channel in a [ShareSheet] that shares permission
/// sets: its name, its set as a preset name or Custom, a remove button, and,
/// when it can change, a [QuarkChatPermissionPicker] under it.
///
/// Clearing every box removes the member rather than saving an empty set, so
/// an empty set from the picker calls [onRevoke].
///
/// A part of [ShareSheet], tested through it.
///
/// Key prefixes: `share_grant_<kind>_<id>` on the row,
/// `share_perms_<kind>_<id>` for its picker's keys, and
/// `share_revoke_<kind>_<id>` on its remove button.
class PermissionGrantRow extends StatelessWidget {
  /// Creates the row for [grant], whose [GrantItem.permissions] is set.
  const PermissionGrantRow({
    required this.grant,
    this.heldPermissions,
    this.canChange = false,
    this.isBusy = false,
    this.onSetPermissions,
    this.onRevoke,
    super.key,
  });

  /// The member this row shows.
  final GrantItem grant;

  /// What the signed-in account may grant; null grants anything, as for an
  /// admin.
  final Set<ChatPermission>? heldPermissions;

  /// Whether this row's set and membership can be changed.
  final bool canChange;

  /// Whether a change to this member is in flight.
  final bool isBusy;

  /// Replaces the set. Null leaves the picker out.
  final ValueChanged<Set<ChatPermission>>? onSetPermissions;

  /// Removes the member. Null disables the button.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final principal = grant.principal;
    final suffix = principal.keySuffix;
    final permissions = grant.permissions ?? const <ChatPermission>{};
    final muted = TextStyle(color: tokens.mutedForeground);
    final setPermissions = canChange ? onSetPermissions : null;
    final revoke = canChange ? onRevoke : null;
    final label = ChatPermissionPreset.labelOf(permissions);

    return Column(
      key: ValueKey('share_grant_$suffix'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            principal.kind == PrincipalKind.user
                ? QuarkIcons.person_outline
                : QuarkIcons.group_outlined,
          ),
          title: Text(
            principal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            principal.isBuiltin ? '$label · Every account' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          trailing: isBusy
              ? const QuarkLoader(size: 24)
              : IconButton(
                  key: ValueKey('share_revoke_$suffix'),
                  tooltip: 'Remove ${principal.name}',
                  icon: const Icon(QuarkIcons.close),
                  onPressed: revoke,
                ),
        ),
        if (setPermissions != null && !isBusy)
          Padding(
            padding: EdgeInsets.only(left: tokens.spacingLg),
            child: QuarkChatPermissionPicker(
              keyPrefix: 'share_perms_$suffix',
              permissions: permissions,
              heldPermissions: heldPermissions,
              onChanged: (next) {
                if (next.isEmpty) {
                  onRevoke?.call();
                } else {
                  setPermissions(next);
                }
              },
            ),
          ),
      ],
    );
  }
}
