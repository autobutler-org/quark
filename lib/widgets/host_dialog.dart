import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/quark_discovery.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/nearby_quarks.dart';

/// Add/edit dialog for a single Quark.
///
/// Owns its text controllers so they live exactly as long as the dialog's
/// element. They used to be created by the caller and disposed in a post-frame
/// callback once `showDialog` resolved, which killed them while the dismiss
/// transition was still running and the fields were still mounted — hence
/// "A TextEditingController was used after being disposed".
///
/// It also only ever pops a [HostEntry]: saving is the caller's job, so the
/// route stack is never mutated while this dialog is on screen (#1623).
///
/// Save checks the address first. An address nothing answers on used to be
/// accepted in silence, which made the active host a dead one and walked the
/// user into terms and a sign-in form for a Quark that was never there
/// (#2032). A failed check keeps the dialog open on the address that failed,
/// because a typo is the likeliest reason; the second press saves it anyway,
/// for the Quark that is simply switched off right now.
///
/// On iOS and Android it also lists the Quarks found on the local network
/// (#2312); tapping one fills in its address, and its name when the nickname
/// is still empty.
class HostDialog extends StatefulWidget {
  const HostDialog({
    super.key,
    required this.isEdit,
    this.initial,
    this.browse,
  });

  final bool isEdit;
  final HostEntry? initial;

  /// Passed to [NearbyQuarks]; a test passes a fake browser.
  final QuarkBrowser? browse;

  @override
  State<HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<HostDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.initial?.hostAddress ?? '',
  );

  /// True while the probe is out.
  bool _checking = false;

  /// The address the probe could not reach, so editing it asks again instead
  /// of offering to save a different address unchecked.
  String? _unreachableAddress;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  /// The address as it will be stored. `addHost` normalizes too; doing it
  /// here keeps the address that is probed and the address that is saved the
  /// same string.
  String get _normalizedAddress => normalizeHostAddress(_address.text.trim());

  bool get _offersSaveAnyway =>
      _unreachableAddress != null && _unreachableAddress == _normalizedAddress;

  Future<void> _submit() async {
    final name = _name.text.trim();
    final address = _normalizedAddress;
    if (name.isEmpty || address.isEmpty || _checking) return;

    final entry = HostEntry(name: name, hostAddress: address);
    if (_offersSaveAnyway) {
      Navigator.of(context).pop(entry);
      return;
    }

    setState(() => _checking = true);
    final reachable = await hostReachabilityProbe(address);
    if (!mounted) return;
    if (!reachable) {
      setState(() {
        _checking = false;
        _unreachableAddress = address;
      });
      return;
    }
    Navigator.of(context).pop(entry);
  }

  /// Fills the form from a Quark found on the network. A nickname already
  /// typed is kept.
  void _pickDiscovered(HostEntry quark) {
    if (_name.text.trim().isEmpty) _name.text = quark.name;
    _address.text = quark.hostAddress;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return QuarkWidget.alertDialog(
      title: Text(widget.isEdit ? 'Edit Quark' : 'Add Quark'),
      // The found Quarks make the content taller than a short screen.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NearbyQuarks(browse: widget.browse, onSelect: _pickDiscovered),
          const SizedBox(height: 8),
          QuarkWidget.textField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            hintText: 'Nickname (e.g. Home)',
          ),
          const SizedBox(height: 8),
          QuarkWidget.textField(
            controller: _address,
            textInputAction: TextInputAction.done,
            // Enter in the address field saves, same as the button.
            onSubmitted: (_) => _submit(),
            // Retyping the address retracts the failure it produced, so the
            // corrected one is checked rather than saved unchecked.
            onChanged: (_) {
              if (_unreachableAddress != null) setState(() {});
            },
            hintText: 'https://quark.local',
          ),
          const SizedBox(height: 6),
          if (_offersSaveAnyway)
            Text(
              key: const ValueKey('host_dialog_unreachable'),
              '${Errors.couldNotConnect} Save anyway to add it now and '
              'connect when it is on.',
              style: TextStyle(fontSize: 12, color: colors.error),
            )
          else
            const Text(
              'Usually https://quark.local or the IP address shown on your device.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const QuarkLoader(size: 16)
              : Text(_offersSaveAnyway ? 'Save anyway' : 'Save'),
        ),
      ],
    );
  }
}
