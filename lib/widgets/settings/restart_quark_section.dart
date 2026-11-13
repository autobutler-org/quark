import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/controllers/restart_controller.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin's restart Quark card on the settings page (#4019).
///
/// Owns a [RestartController]. Offers **Restart Quark** after asking first,
/// shows "Restarting…" until the Quark answers again, then says it is back.
/// Renders nothing unless the Quark says something will start it again
/// after it exits.
///
/// Key prefixes: `restart_quark_button`.
class RestartQuarkSection extends StatefulWidget {
  /// Creates the section, with the real services unless [controller] is
  /// given.
  const RestartQuarkSection({this.controller, super.key});

  /// Injected for tests. Created and disposed here when null.
  final RestartController? controller;

  @override
  State<RestartQuarkSection> createState() => _RestartQuarkSectionState();
}

class _RestartQuarkSectionState extends State<RestartQuarkSection> {
  late final RestartController _controller =
      widget.controller ?? RestartController();

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

  Future<void> _restart() async {
    final confirmed = await confirmAction(
      context,
      title: 'Restart Quark?',
      message:
          'Quark will turn off and back on. It will be unavailable for a few '
          'seconds, and anything in progress, like an upload, will stop.',
      confirmLabel: 'Restart',
    );
    if (confirmed != true) return;
    await _controller.restart();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.isAvailable) return const SizedBox.shrink();
        final error = _controller.error;
        final busy = _controller.isWorking || _controller.isRestarting;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: QuarkSection(
            title: 'Restart Quark',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Turn Quark off and back on, if something is not '
                      'working the way it should.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('restart_quark_button'),
                      onPressed: busy ? null : _restart,
                      icon: const Icon(QuarkIcons.restart),
                      label: const Text('Restart Quark'),
                    ),
                    if (_controller.isRestarting) ...[
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          QuarkLoader(size: 20),
                          SizedBox(width: 12),
                          Flexible(child: Text('Restarting…')),
                        ],
                      ),
                    ],
                    if (_controller.isBack) ...[
                      const SizedBox(height: 12),
                      const Text('Quark is back.'),
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
