import 'package:flutter/material.dart';

import '../../chat/quark_chat_permission_picker.dart';
import '../../core/quark_loader.dart';
import '../../models/chat_permission.dart';
import '../../models/chat_permission_preset.dart';
import '../../models/principal_item.dart';
import '../../theme/quark_tokens.dart';
import '../../users/principal_picker.dart';

/// The part of a [ShareSheet] that adds someone to a chat channel: a
/// [PrincipalPicker], a [QuarkChatPermissionPicker] starting at Member (or
/// at what the signed-in account holds, when that is less), and an add
/// button.
///
/// The picked account or group and the set are [State] because they are the
/// form's own transient input; the outcome leaves through [onAdd]. An empty
/// set adds no one, so the button stays off until something is ticked.
///
/// A part of [ShareSheet], tested through it.
///
/// Key prefixes: `share_add_perms` for the picker's keys, `share_add_submit`
/// on the add button, and the [PrincipalPicker] keys.
class AddPermissionGrantForm extends StatefulWidget {
  /// Creates the form offering [principals].
  const AddPermissionGrantForm({
    required this.principals,
    required this.onAdd,
    this.heldPermissions,
    this.busyKeys = const {},
    super.key,
  });

  /// The accounts and groups to pick from.
  final List<PrincipalItem> principals;

  /// Called with the picked account or group and the chosen set.
  final void Function(PrincipalItem principal, Set<ChatPermission> permissions)
  onAdd;

  /// What the signed-in account may grant; null grants anything.
  final Set<ChatPermission>? heldPermissions;

  /// Key suffixes of principals with a change in flight. The add button
  /// shows progress while the picked one is among them.
  final Set<String> busyKeys;

  @override
  State<AddPermissionGrantForm> createState() => _AddPermissionGrantFormState();
}

class _AddPermissionGrantFormState extends State<AddPermissionGrantForm> {
  PrincipalItem? _picked;
  Set<ChatPermission>? _permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final picked = _picked;
    final held = widget.heldPermissions;
    // Nothing the caller can't grant, even after their own set shrinks.
    final permissions = {
      ...(_permissions ?? ChatPermissionPreset.member.permissions),
    }..removeWhere((p) => held != null && !held.contains(p));
    final isBusy = picked != null && widget.busyKeys.contains(picked.keySuffix);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add to the channel',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: tokens.spacingSm),
        PrincipalPicker(
          options: widget.principals,
          selected: picked,
          searchLabel: 'Search accounts and groups',
          onSelected: (principal) => setState(() => _picked = principal),
        ),
        SizedBox(height: tokens.spacingSm),
        QuarkChatPermissionPicker(
          keyPrefix: 'share_add_perms',
          permissions: ChatPermission.withPrerequisites(permissions),
          heldPermissions: held,
          onChanged: (next) => setState(() => _permissions = next),
        ),
        SizedBox(height: tokens.spacingSm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const ValueKey('share_add_submit'),
            onPressed: picked == null || isBusy || permissions.isEmpty
                ? null
                : () => widget.onAdd(
                    picked,
                    ChatPermission.withPrerequisites(permissions),
                  ),
            child: isBusy ? const QuarkLoader(size: 20) : const Text('Add'),
          ),
        ),
      ],
    );
  }
}
