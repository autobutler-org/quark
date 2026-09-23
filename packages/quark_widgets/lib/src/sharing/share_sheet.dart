import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../models/access_level.dart';
import '../models/grant_item.dart';
import '../models/principal_item.dart';
import '../theme/quark_tokens.dart';
import 'share_sheet/add_grant_form.dart';
import 'share_sheet/grant_row.dart';

/// Who has access to one file or folder, controls to change it, and a form
/// to share it with another account or group.
///
/// Every value is the caller's: [grants] and [principals] in, [onAdd],
/// [onSetLevel] and [onRevoke] out, and the caller replaces [grants] once a
/// change lands. A row with a change in flight, in [busyKeys], shows progress
/// in place of its controls.
///
/// Access set on the item itself is listed first, each row with a level menu
/// and a remove button. Access inherited from a folder the item is in is
/// listed under **Inherited access**, read-only and naming that folder,
/// because it can only be changed there. The same account or group can
/// appear in both lists.
///
/// Only a caller who manages sharing, [canManage], gets the form and working
/// controls. The owner level, and changing an owner row, also needs
/// [canGrantOwner]. A row whose [PrincipalItem.keySuffix] is in [lockedKeys]
/// stays read-only either way, such as the caller's own ownership.
///
/// The caller confirms whatever deserves it, such as removing an owner,
/// before acting on a callback. Show the sheet with
/// `showModalBottomSheet(isScrollControlled: true, ...)`: it scrolls itself
/// and moves clear of the keyboard.
///
/// Key prefixes, where `<kind>_<id>` is [PrincipalItem.keySuffix]:
/// `share_grant_<kind>_<id>` on each row set on the item,
/// `share_level_<kind>_<id>` on its level menu,
/// `share_level_<kind>_<id>_<level>` on the menu entries,
/// `share_revoke_<kind>_<id>` on its remove button,
/// `share_inherited_<kind>_<id>` on each inherited row,
/// `share_add_level_<level>` on the form's level choices, `share_add_submit`
/// on its share button, and the principal picker's `principal_search` and
/// `principal_option_<kind>_<id>`.
///
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   isScrollControlled: true,
///   builder: (context) => ShareSheet(
///     itemName: 'Recipes',
///     grants: controller.grants,
///     principals: controller.principals,
///     canManage: controller.canManage,
///     canGrantOwner: controller.canGrantOwner,
///     lockedKeys: controller.lockedKeys,
///     busyKeys: controller.busyKeys,
///     error: shareError,
///     onAdd: add,
///     onSetLevel: setLevel,
///     onRevoke: confirmRevoke,
///   ),
/// );
/// ```
class ShareSheet extends StatelessWidget {
  /// Creates the sheet for the item named [itemName].
  const ShareSheet({
    required this.itemName,
    required this.grants,
    required this.principals,
    this.canManage = false,
    this.canGrantOwner = false,
    this.lockedKeys = const {},
    this.busyKeys = const {},
    this.isLoading = false,
    this.error,
    this.onAdd,
    this.onSetLevel,
    this.onRevoke,
    super.key,
  });

  /// The name of the file or folder being shared, shown in the title.
  final String itemName;

  /// Everyone with access, set on the item or inherited, in the order shown
  /// within each list.
  final List<GrantItem> grants;

  /// The accounts and groups the form offers to share with.
  final List<PrincipalItem> principals;

  /// Whether the caller may change who has access. False leaves the form out
  /// and every control disabled.
  final bool canManage;

  /// Whether the caller may give the owner level, or change an owner row.
  final bool canGrantOwner;

  /// Key suffixes of rows set on the item that stay read-only even for a
  /// manager.
  final Set<String> lockedKeys;

  /// Key suffixes of principals with a change in flight.
  final Set<String> busyKeys;

  /// Whether the access is still loading. Shows a spinner in place of the
  /// lists and the form.
  final bool isLoading;

  /// A sentence saying why loading or the last change failed, composed by
  /// the caller. Shown under the title.
  final String? error;

  /// Called with who to share with and at what level. Null leaves the form
  /// out.
  final void Function(PrincipalItem principal, AccessLevel level)? onAdd;

  /// Called with whose access to change and the new level. Null disables the
  /// level menus.
  final void Function(PrincipalItem principal, AccessLevel level)? onSetLevel;

  /// Called with whose access to remove. Null disables the remove buttons.
  final ValueChanged<PrincipalItem>? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onAdd = this.onAdd;
    final onSetLevel = this.onSetLevel;
    final onRevoke = this.onRevoke;
    final direct = [
      for (final grant in grants)
        if (!grant.isInherited) grant,
    ];
    final inherited = [
      for (final grant in grants)
        if (grant.isInherited) grant,
    ];
    // A load that failed has nothing to show but its reason.
    final hasAccess = canManage || grants.isNotEmpty;
    final heading = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share $itemName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (error != null) ...[
                SizedBox(height: tokens.spacingSm),
                Text(error, style: TextStyle(color: tokens.error)),
              ],
              SizedBox(height: tokens.spacingSm),
              if (isLoading)
                Padding(
                  padding: EdgeInsets.all(tokens.spacingLg),
                  child: const Center(child: QuarkLoader()),
                )
              else if (hasAccess) ...[
                if (canManage && onAdd != null) ...[
                  AddGrantForm(
                    principals: principals,
                    canGrantOwner: canGrantOwner,
                    busyKeys: busyKeys,
                    onAdd: onAdd,
                  ),
                  SizedBox(height: tokens.spacingMd),
                ],
                Text('Who has access', style: heading),
                SizedBox(height: tokens.spacingXs),
                if (direct.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
                    child: Text(
                      'No one has access set on this item',
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                  )
                else
                  for (final grant in direct)
                    GrantRow(
                      grant: grant,
                      isBusy: busyKeys.contains(grant.principal.keySuffix),
                      canGrantOwner: canGrantOwner,
                      canChange:
                          canManage &&
                          !lockedKeys.contains(grant.principal.keySuffix) &&
                          (grant.level != AccessLevel.owner || canGrantOwner),
                      onSetLevel: onSetLevel == null
                          ? null
                          : (level) => onSetLevel(grant.principal, level),
                      onRevoke: onRevoke == null
                          ? null
                          : () => onRevoke(grant.principal),
                    ),
                if (inherited.isNotEmpty) ...[
                  SizedBox(height: tokens.spacingMd),
                  Text('Inherited access', style: heading),
                  SizedBox(height: tokens.spacingXs),
                  for (final grant in inherited) GrantRow(grant: grant),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
