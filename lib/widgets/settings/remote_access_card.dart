import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/remote_access_controller.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/remote_access_config.dart';
import 'package:quark/widgets/settings/help_support_card.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Remote access card on the Network tab of Settings: the Quark's
/// remote access [status] as the package [RemoteAccessPanel] shows it, with
/// the app's own error copy from [Errors].
///
/// Keys: those of [RemoteAccessPanel].
class RemoteAccessCard extends StatelessWidget {
  /// Creates the card.
  const RemoteAccessCard({
    required this.status,
    required this.isLoading,
    required this.isWorking,
    required this.error,
    required this.disconnected,
    required this.isAdmin,
    required this.onRetry,
    required this.onSetUp,
    required this.onTurnOff,
    required this.onTryAgain,
    this.onGetHelp = openSupportPage,
    super.key,
  });

  /// The last status read, or null before the first.
  final RemoteAccessStatus? status;

  /// Whether the status is being read.
  final bool isLoading;

  /// Whether turning remote access on or off is in flight.
  final bool isWorking;

  /// Why the status could not be read, or null.
  final String? error;

  /// Whether the Quark is unreachable, which the page banner explains, so
  /// the card says so in a word instead of repeating [error].
  final bool disconnected;

  /// Whether the user may turn remote access on or off.
  final bool isAdmin;

  /// Reads the status again.
  final VoidCallback onRetry;

  /// Opens the setup sheet.
  final VoidCallback onSetUp;

  /// Asks to turn remote access off for everyone.
  final VoidCallback onTurnOff;

  /// Turns remote access on again after it failed to connect.
  final VoidCallback onTryAgain;

  /// Opens help while remote access is failing. The support page by
  /// default, in the browser, so the failure stays on screen (#2902).
  final VoidCallback onGetHelp;

  /// Opens [HelpSupportCard.supportUrl] in the browser.
  static void openSupportPage() => unawaited(
    launchUrl(
      Uri.parse(HelpSupportCard.supportUrl),
      mode: LaunchMode.externalApplication,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return RemoteAccessPanel(
      state: RemoteAccessController.stateOf(status),
      isAdmin: isAdmin,
      isLoading: isLoading,
      isWorking: isWorking,
      available: RemoteAccessConfig.enableAvailable,
      error: error == null
          ? null
          : (disconnected ? quarkDisconnectedShort : error),
      failure: Errors.remoteAccessFailing,
      failureSteps: Errors.remoteAccessFailingSteps,
      onRetry: onRetry,
      onSetUp: onSetUp,
      onTurnOff: onTurnOff,
      onTryAgain: onTryAgain,
      onGetHelp: onGetHelp,
    );
  }
}
