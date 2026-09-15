import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/share_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the share sheet for the file or folder at [relPath] on the device
/// [deviceSerial], titled with its [name] (#1911).
///
/// A [ShareController] lives as long as the sheet is open. A refusal shows in
/// the sheet, where a snack bar would be hidden under it. Removing an owner,
/// or giving an owner a lower level, asks first: with no other owner left,
/// only admins can change who has access.
Future<void> showShareSheet(
  BuildContext context, {
  required String deviceSerial,
  required String relPath,
  required String name,
}) async {
  final settings = AppSettings.instance;
  final controller = ShareController(
    deviceSerial: deviceSerial,
    relPath: relPath,
    selfUsername: settings.username,
    isAdmin: settings.isAdmin.value,
  );
  final message = ValueNotifier<String?>(null);
  unawaited(controller.load());

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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

        final loadError = controller.error;
        return ShareSheet(
          itemName: name,
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
          onRevoke: (principal) async {
            if (controller.losesOwnership(principal, null) &&
                !await _confirmOwnerChange(
                  sheetContext,
                  principal: principal,
                  itemName: name,
                  removing: true,
                )) {
              return;
            }
            await report(controller.revoke(principal), 'remove access');
          },
        );
      },
    ),
  );

  message.dispose();
  controller.dispose();
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
