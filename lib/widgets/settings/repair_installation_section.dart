import 'package:flutter/material.dart';
import 'package:quark/controllers/repair_controller.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/settings/code_block.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's repair installation card on the settings page (#2121).
///
/// Owns a [RepairController]. Offers **Repair installation** when a restart
/// will reapply the system setup, the one-time `sudo quark install` when the
/// installed unit is too old for that, and renders nothing on a Quark that is
/// not the installed Linux service.
///
/// Key prefixes: `repair_installation_button`.
class RepairInstallationSection extends StatefulWidget {
  /// Creates the section, with the real service unless [controller] is given.
  const RepairInstallationSection({this.controller, super.key});

  /// Injected for tests. Created and disposed here when null.
  final RepairController? controller;

  /// The command that installs a unit new enough to repair itself.
  static const String installCommand = 'sudo quark install';

  @override
  State<RepairInstallationSection> createState() =>
      _RepairInstallationSectionState();
}

class _RepairInstallationSectionState extends State<RepairInstallationSection> {
  late final RepairController _controller =
      widget.controller ?? RepairController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _repair() async {
    final confirmed = await confirmAction(
      context,
      title: 'Repair installation?',
      message:
          "Quark will restart and reapply its system setup. It will be "
          'unavailable for a few seconds.',
      confirmLabel: 'Repair',
    );
    if (confirmed != true) return;
    if (!await _controller.repair() || !mounted) return;
    // The same handling the update flow gives a restart: say it is happening.
    // While it is down, the page's disconnected banner explains the failures.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quark is restarting. It will be back in a few seconds.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.isHidden) return const SizedBox.shrink();
        final status = _controller.status;
        final error = _controller.error;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: QuarkSection(
            title: 'Repair installation',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_controller.isLoading && status == null)
                      const Center(child: CircularProgressIndicator())
                    else if (_controller.needsInstall) ...[
                      const Text(
                        'This Quark was installed before it could repair '
                        'itself. Run this once on the device to repair it:',
                      ),
                      const SizedBox(height: 8),
                      const CodeBlock(
                        text: RepairInstallationSection.installCommand,
                      ),
                    ] else if (status != null && status.available) ...[
                      const Text(
                        "Restart Quark and reapply its system setup, if "
                        "something on the device has drifted.",
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('repair_installation_button'),
                        onPressed: _controller.isWorking ? null : _repair,
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Repair installation'),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
