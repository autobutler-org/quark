import 'package:flutter/material.dart';

import '../models/chat_permission.dart';
import '../models/chat_permission_preset.dart';
import '../theme/quark_tokens.dart';

/// Picks what a member of a chat channel may do: one of the presets
/// (Viewer, Member, Moderator, Owner), or Custom, which opens a checkbox for
/// each [ChatPermission] (#2415, #2422).
///
/// The set is the caller's: [permissions] in, [onChanged] out with the whole
/// new set. A set that matches a preset selects its chip; anything else
/// selects Custom and starts with the checkboxes open. Ticking a permission
/// ticks what it needs, and clearing one clears what needs it, so the set
/// the caller gets is always coherent: clearing `read_messages` clears the
/// message permissions and leaves the management ones, since a manage-only
/// set is a delegated manager. An empty set is not a member at all, and the
/// picker says so with [emptyHint]; the caller removes rather than saves it.
///
/// Permissions the signed-in account doesn't hold, missing from
/// [heldPermissions], can't be granted: their boxes are disabled with
/// [notHeldReason], and a preset that includes one is disabled too. The Quark
/// refuses the same grant, so the picker never offers one that would fail.
///
/// The open checklist is Flutter's own expansion state, kept in an
/// [ExpansibleController]; it doesn't animate, so it needs no reduced-motion
/// variant. Open, the picker is as tall as seven rows, so it sits in a
/// scrolling parent such as a sheet.
///
/// Key prefixes, where `<prefix>` is [keyPrefix]:
/// `<prefix>_preset_<name>` on each preset chip (`viewer`, `member`,
/// `moderator`, `owner`), `<prefix>_preset_custom` on the Custom chip,
/// `<prefix>_custom` on the checklist, `<prefix>_<id>` on each checkbox,
/// such as `chat_permission_send_messages`, and `<prefix>_empty` on the
/// empty-set hint.
///
/// ```dart
/// QuarkChatPermissionPicker(
///   permissions: member.permissions,
///   heldPermissions: controller.selectedPermissions,
///   onChanged: (permissions) => controller.setMember(member, permissions),
/// );
/// ```
class QuarkChatPermissionPicker extends StatefulWidget {
  /// Creates a picker showing [permissions].
  const QuarkChatPermissionPicker({
    required this.permissions,
    this.heldPermissions,
    this.onChanged,
    this.keyPrefix = 'chat_permission',
    super.key,
  });

  /// The set being edited.
  final Set<ChatPermission> permissions;

  /// What the signed-in account holds, and so may grant. Null holds
  /// everything, as for an admin.
  final Set<ChatPermission>? heldPermissions;

  /// Called with the whole new set. Null disables every control.
  final ValueChanged<Set<ChatPermission>>? onChanged;

  /// What every key in the picker starts with, so two pickers on one screen
  /// don't share keys.
  final String keyPrefix;

  /// Shown on a permission the signed-in account can't grant.
  static const String notHeldReason =
      "You can't grant a permission you don't have";

  /// Shown when nothing is ticked.
  static const String emptyHint =
      'With nothing ticked, they are removed from the channel';

  @override
  State<QuarkChatPermissionPicker> createState() =>
      _QuarkChatPermissionPickerState();
}

class _QuarkChatPermissionPickerState extends State<QuarkChatPermissionPicker> {
  final ExpansibleController _custom = ExpansibleController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool _holds(ChatPermission permission) =>
      widget.heldPermissions?.contains(permission) ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final permissions = widget.permissions;
    final onChanged = widget.onChanged;
    final prefix = widget.keyPrefix;
    final preset = ChatPermissionPreset.of(permissions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingSm,
          children: [
            for (final option in ChatPermissionPreset.values)
              ChoiceChip(
                key: ValueKey('${prefix}_preset_${option.name}'),
                label: Text(option.label),
                selected: option == preset,
                onSelected:
                    onChanged == null || !option.permissions.every(_holds)
                    ? null
                    : (_) => onChanged(option.permissions),
              ),
            ChoiceChip(
              key: ValueKey('${prefix}_preset_custom'),
              label: const Text(ChatPermissionPreset.customLabel),
              selected: preset == null,
              onSelected: onChanged == null ? null : (_) => _custom.expand(),
            ),
          ],
        ),
        if (permissions.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacingSm),
            child: Text(
              QuarkChatPermissionPicker.emptyHint,
              key: ValueKey('${prefix}_empty'),
              style: TextStyle(color: tokens.warning),
            ),
          ),
        ExpansionTile(
          key: ValueKey('${prefix}_custom'),
          controller: _custom,
          initiallyExpanded: preset == null,
          expansionAnimationStyle: AnimationStyle.noAnimation,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            'Permissions',
            style: TextStyle(color: tokens.secondaryForeground),
          ),
          children: [
            for (final permission in ChatPermission.values)
              CheckboxListTile(
                key: ValueKey('${prefix}_${permission.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: permissions.contains(permission),
                title: Text(permission.label),
                subtitle: Text(
                  _holds(permission)
                      ? permission.description
                      : QuarkChatPermissionPicker.notHeldReason,
                  style: TextStyle(color: tokens.mutedForeground),
                ),
                onChanged: onChanged == null || !_holds(permission)
                    ? null
                    : (ticked) => onChanged(
                        ticked ?? false
                            ? ChatPermission.withPrerequisites({
                                ...permissions,
                                permission,
                              })
                            : ChatPermission.withoutDependents(
                                permissions,
                                permission,
                              ),
                      ),
              ),
          ],
        ),
      ],
    );
  }
}
