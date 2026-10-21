import 'package:flutter/material.dart';
import 'package:quark/controllers/recovery_phrase_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The offer the vault and chat pages show over keys that have no wrap under
/// the recovery phrase (#3530), as a child of the page body's [Column]:
/// [RecoveryPhraseOffer], whose add button asks
/// for the phrase and the password in an [AddRecoveryPhraseDialog] and hands
/// them to [controller].
///
/// The dialog stays open with what was typed until the phrase is added, and
/// shows why it was not. A phrase that is not the account's changes nothing,
/// since the Quark checks it before anything is stored. Once it is added a
/// snack bar says so and [controller] stops offering.
class AddRecoveryPhraseOffer extends StatelessWidget {
  /// Creates the offer over [controller].
  const AddRecoveryPhraseOffer({required this.controller, super.key});

  /// Says whether to offer, and adds the phrase.
  final RecoveryPhraseController controller;

  /// What the offer says a phrase keeps.
  static const String message =
      'Add your recovery phrase so a recovery keeps your vault and messages.';

  /// Said once the phrase is added.
  static const String added =
      'Recovery phrase added. A recovery now keeps your vault and messages.';

  Future<void> _add(BuildContext context) async {
    controller.clearError();
    final done = await QuarkWidget.showDialog<bool>(
      context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => AddRecoveryPhraseDialog(
          isBusy: controller.isBusy,
          error: controller.error == null
              ? null
              : Errors.message(controller.error, 'add your recovery phrase'),
          onSubmit: (phrase, password) async {
            final ok = await controller.add(password: password, phrase: phrase);
            if (ok && dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          },
          onCancel: () => Navigator.of(dialogContext).pop(false),
        ),
      ),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(added)));
    }
  }

  /// Scrolls within its share of a page's [Column] rather than squeezing what
  /// sits under it on a short phone: it takes what it needs, up to the
  /// space a single [Expanded] sibling is left.
  @override
  Widget build(BuildContext context) => Flexible(
    child: SingleChildScrollView(
      child: RecoveryPhraseOffer(
        message: message,
        onAdd: () => _add(context),
        onDismiss: controller.dismiss,
      ),
    ),
  );
}
