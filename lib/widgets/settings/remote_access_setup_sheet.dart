import 'package:flutter/material.dart';
import 'package:quark/controllers/remote_access_controller.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Shows the remote access setup sheet over [context] and completes when it
/// closes. Setup carries on on the Quark if the sheet is closed early.
Future<void> showRemoteAccessSetupSheet(
  BuildContext context,
  RemoteAccessController controller,
) => showQuarkSheet<void>(
  context,
  title: 'Remote access',
  builder: (sheetContext) => RemoteAccessSetupSheet(
    controller: controller,
    onClose: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The remote access setup sheet's content (#2857): the package
/// [RemoteAccessSetupView], moved along by [controller] as the Quark turns
/// remote access on and connects.
///
/// It starts at the intro whatever the Quark is doing, and only follows the
/// controller once Turn on is tapped here. If the Quark then reports it
/// could not connect, the sheet closes and the Network tab shows the failure
/// and what to try. A refused request stays on the intro with a snack bar.
class RemoteAccessSetupSheet extends StatefulWidget {
  /// Creates the sheet's content.
  const RemoteAccessSetupSheet({
    required this.controller,
    required this.onClose,
    super.key,
  });

  /// Where the Quark's remote access state comes from.
  final RemoteAccessController controller;

  /// Closes the sheet.
  final VoidCallback onClose;

  @override
  State<RemoteAccessSetupSheet> createState() => _RemoteAccessSetupSheetState();
}

class _RemoteAccessSetupSheetState extends State<RemoteAccessSetupSheet> {
  /// Whether Turn on was tapped in this sheet.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (_started && widget.controller.state == RemoteAccessState.failing) {
      widget.onClose();
    }
  }

  Future<void> _turnOn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _started = true);
    final error = await widget.controller.enable();
    if (error == null) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
    if (mounted) setState(() => _started = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => RemoteAccessSetupView(
        stage: _started
            ? widget.controller.setupStage
            : RemoteAccessSetupStage.intro,
        onTurnOn: _turnOn,
        onNotNow: widget.onClose,
        onDone: widget.onClose,
      ),
    );
  }
}
