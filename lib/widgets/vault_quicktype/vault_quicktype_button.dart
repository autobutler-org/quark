import 'package:flutter/material.dart';
import 'package:quark/controllers/quicktype_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open vault's bar button for QuickType suggestions (#3599), and the
/// setting it opens: a switch, and what turning it on stores unencrypted,
/// said before it is on.
///
/// Shows nothing unless [QuickTypeController.isAvailable]: iOS, with
/// biometric unlock on. The dialog is the package's settings dialog over
/// [QuickTypeController.setEnabled], inside a `KeyedSubtree` keyed
/// `vault_quicktype_settings`; the button is keyed
/// `vault_quicktype_button`.
class VaultQuickTypeButton extends StatelessWidget {
  /// Creates the button over [controller], the app's by default.
  const VaultQuickTypeButton({this.controller, this.onOpen, super.key});

  /// The setting. Tests pass one with fakes.
  final QuickTypeController? controller;

  /// Called as the dialog opens: the vault page restarts its idle timer.
  final VoidCallback? onOpen;

  Future<void> _open(BuildContext context, QuickTypeController quickType) {
    onOpen?.call();
    return QuarkWidget.showDialog<void>(
      context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: quickType,
        builder: (_, _) => KeyedSubtree(
          key: const ValueKey('vault_quicktype_settings'),
          child: VaultBiometricSettingsDialog(
            title: QuickTypeController.settingTitle,
            explanation: quickType.settingExplanation,
            value: quickType.enabled,
            isBusy: quickType.isBusy,
            error: quickType.error == null
                ? null
                : Errors.message(quickType.error, 'change this setting'),
            onChanged: quickType.setEnabled,
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickType = controller ?? QuickTypeController.instance;
    return ListenableBuilder(
      listenable: quickType,
      builder: (context, _) => quickType.isAvailable
          ? QuarkBarIconButton(
              key: const ValueKey('vault_quicktype_button'),
              icon: QuarkIcons.keyboard_outlined,
              tooltip: 'QuickType suggestions',
              onPressed: () => _open(context, quickType),
            )
          : const SizedBox.shrink(),
    );
  }
}
