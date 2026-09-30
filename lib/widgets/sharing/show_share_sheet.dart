import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/share_controller.dart';
import 'package:quark/controllers/share_target.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the share sheet for the file or folder at [relPath] on the device
/// [deviceSerial], titled with its [name] (#1911).
Future<void> showShareSheet(
  BuildContext context, {
  required String deviceSerial,
  required String relPath,
  required String name,
}) => showShareSheetFor(
  context,
  target: PathShareTarget(deviceSerial: deviceSerial, relPath: relPath),
  name: name,
);

/// Opens the share sheet for [target], a path or a chat channel (#2422),
/// titled with its [name].
///
/// A [ShareController] lives as long as the sheet is open. A refusal shows in
/// the sheet, where a snack bar would be hidden under it. Removing an owner,
/// or giving an owner a lower level, asks first: with no other owner left,
/// only admins can change who has access. A channel shares permission sets
/// instead, and taking `read_messages` away from someone who had it, by
/// removing them or changing their set, warns first that the key will
/// rotate and that they keep what they already downloaded.
Future<void> showShareSheetFor(
  BuildContext context, {
  required ShareTarget target,
  required String name,
}) async {
  final settings = AppSettings.instance;
  final controller = ShareController(
    target: target,
    selfUsername: settings.username,
    isAdmin: settings.isAdmin.value,
  );
  final message = ValueNotifier<String?>(null);
  unawaited(controller.load());

  await showQuarkSheet<void>(
    context,
    title: 'Share $name',
    builder: (sheetContext) => ListenableBuilder(
      listenable: Listenable.merge([controller, message]),
      builder: (sheetContext, _) {
        Future<void> report(Future<Object?> change, String action) async {
          final error = await change;
          if (!sheetContext.mounted) return;
          message.value = error == null ? null : Errors.message(error, action);
        }

        // The share form and a row's level both land here, so neither
        // demotes an owner without asking.
        Future<void> setLevel(
          PrincipalItem principal,
          AccessLevel level,
          String action,
        ) async {
          if (controller.losesOwnership(principal, level) &&
              !await _confirmOwnerChange(
                sheetContext,
                principal: principal,
                itemName: name,
                removing: false,
              )) {
            return;
          }
          await report(controller.share(principal, level), action);
        }

        // A row's set and the add form both land here, so neither takes a
        // key away without a warning.
        Future<void> setPermissions(
          PrincipalItem principal,
          Set<ChatPermission> permissions,
          String action,
        ) async {
          if (controller.losesKey(principal, permissions) &&
              !await _confirmKeyRotation(
                sheetContext,
                principal: principal,
                itemName: name,
                removing: false,
              )) {
            return;
          }
          await report(
            controller.sharePermissions(principal, permissions),
            action,
          );
        }

        final loadError = controller.error;
        return ShareSheet(
          grants: controller.grants,
          principals: controller.principals,
          canManage: controller.canManage,
          canGrantOwner: controller.canGrantOwner,
          lockedKeys: controller.lockedKeys,
          busyKeys: controller.busyKeys,
          isLoading: !controller.hasLoaded && loadError == null,
          error:
              message.value ??
              (loadError == null
                  ? null
                  : Errors.message(loadError, 'load sharing')),
          onAdd: (principal, level) => setLevel(principal, level, 'share this'),
          onSetLevel: (principal, level) =>
              setLevel(principal, level, 'change access'),
          heldPermissions: controller.heldPermissions,
          onAddPermissions: (principal, permissions) =>
              setPermissions(principal, permissions, 'add them'),
          onSetPermissions: (principal, permissions) =>
              setPermissions(principal, permissions, 'change permissions'),
          onRevoke: (principal) async {
            // A channel warns about its key, a path about its owners.
            final confirmed = controller.heldPermissions != null
                ? !controller.losesKey(principal, null) ||
                      await _confirmKeyRotation(
                        sheetContext,
                        principal: principal,
                        itemName: name,
                        removing: true,
                      )
                : !controller.losesOwnership(principal, null) ||
                      await _confirmOwnerChange(
                        sheetContext,
                        principal: principal,
                        itemName: name,
                        removing: true,
                      );
            if (!confirmed) return;
            await report(controller.revoke(principal), 'remove access');
          },
        );
      },
    ),
  );

  message.dispose();
  controller.dispose();
}

/// Warns before [principal] loses `read_messages` on channel [itemName], by
/// being removed or by a new set: the key rotates, and what they already
/// downloaded stays with them. True when confirmed.
Future<bool> _confirmKeyRotation(
  BuildContext context, {
  required PrincipalItem principal,
  required String itemName,
  required bool removing,
}) async {
  final who = principal.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ConfirmDeleteDialog(
      title: removing
          ? 'Remove $who from $itemName?'
          : 'Stop $who reading $itemName?',
      body:
          "The channel's key will change, so $who can't read anything posted "
          'from now on. They keep whatever they already downloaded.',
      keyPrefix: 'rotate_key',
      confirmLabel: removing ? 'Remove' : 'Change',
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  return confirmed == true;
}

/// Asks before [principal] stops being an owner of [itemName], by removing
/// their access or by giving them a lower level. True when confirmed.
Future<bool> _confirmOwnerChange(
  BuildContext context, {
  required PrincipalItem principal,
  required String itemName,
  required bool removing,
}) async {
  final who = principal.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ConfirmDeleteDialog(
      title: removing ? "Remove $who's access?" : 'Stop $who being an owner?',
      body:
          '$who is an owner of $itemName. If no other owner is left, only '
          'admins can change who has access to it.',
      keyPrefix: removing ? 'revoke_owner' : 'demote_owner',
      confirmLabel: removing ? 'Remove' : 'Change',
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  return confirmed == true;
}
