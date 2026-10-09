import 'package:flutter/material.dart';
import 'package:quark/controllers/hostname_controller.dart';
import 'package:quark/widgets/settings/hostname_field.dart';

/// The device name section of Settings and of first-boot setup (#2344): a
/// heading over a card holding the [HostnameField].
///
/// Owns a [HostnameController] and maps it into the field. It takes no space
/// at all unless the Quark says it can be renamed, so it is absent while the
/// status loads, when the Quark could not be asked (an older Quark, a
/// member), and on a Quark that is not the installed Linux service. When it
/// shows it ends with its own gap, so a parent needs no spacing that would be
/// left behind when it does not.
///
/// Key: `hostname_section`, on the section while it shows.
class HostnameSection extends StatefulWidget {
  /// Creates the section, with the real service unless [controller] is given.
  const HostnameSection({
    this.controller,
    this.title = 'Device name',
    super.key,
  });

  /// Injected for tests. Created and disposed here when null.
  final HostnameController? controller;

  /// The heading above the card.
  final String title;

  @override
  State<HostnameSection> createState() => _HostnameSectionState();
}

class _HostnameSectionState extends State<HostnameSection> {
  late final HostnameController _controller =
      widget.controller ?? HostnameController();

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final status = _controller.status;
        if (status == null || !status.available) {
          return const SizedBox.shrink();
        }
        return Column(
          key: const ValueKey('hostname_section'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: HostnameField(
                  hostname: status.hostname,
                  advertisedHostname: status.advertisedHostname,
                  isWorking: _controller.isWorking,
                  error: _controller.error,
                  renamedTo: _controller.renamedTo,
                  reopenAddress: _controller.reopenAddress,
                  onSubmit: _controller.rename,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
