import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/quark_discovery.dart';
import 'package:quark/widgets/hosts/emulator_loopback_hint.dart';
import 'package:quark/widgets/nearby_quarks.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/utils/error_text.dart';

/// First-run "point me at a Quark" form.
///
/// Shown wherever the app has no host configured at all — the login page
/// (#1639) and the file browser's first-run state.
///
/// On iOS and Android it also lists the Quarks found on the local network
/// (#2312); tapping one fills in its address. Typing one stays the fallback,
/// and a typed local name that does not answer is retried as `.local`, `.lan`
/// and bare before the form gives up (#2518).
///
/// On Android a typed `localhost` gets an [EmulatorLoopbackHint] under the
/// field (#2070).
class QuarkConnectForm extends StatefulWidget {
  const QuarkConnectForm({
    super.key,
    required this.onConnected,
    this.autofocus = true,
    this.browse,
  });

  /// Fired once the address has been saved as the active host.
  final VoidCallback onConnected;

  final bool autofocus;

  /// Passed to [NearbyQuarks]; a test passes a fake browser.
  final QuarkBrowser? browse;

  @override
  State<QuarkConnectForm> createState() => _QuarkConnectFormState();
}

class _QuarkConnectFormState extends State<QuarkConnectForm> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter your Quark address.');
      return;
    }

    // A quark serves TLS; a schemeless address must become https://.
    // addHost normalizes too — doing it here keeps the value we show and the
    // value we store identical.
    final address = normalizeHostAddress(raw);

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Checked before it is saved (#2032). This form's whole job is the
      // address, and it already owns the copy for an address that does not
      // answer — it just never asked. Saving first meant a typo became the
      // active host and the user met terms and a sign-in form instead of
      // this field.
      //
      // A local name that does not answer is retried under its sibling names
      // (#2518): a router that appends `.lan` may answer for `quark.lan` when
      // the phone cannot resolve the `quark.local` the hint suggests. The name
      // that answered is the one saved.
      final reachable = await firstReachableAddress(
        address,
        hostReachabilityProbe,
      );
      if (reachable == null) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = Errors.couldNotConnect;
          });
        }
        return;
      }
      await AppSettings.instance.addHost(
        HostEntry(name: 'My Quark', hostAddress: reachable),
      );
      if (mounted) widget.onConnected();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = Errors.couldNotConnect;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(QuarkIcons.storage_outlined, size: 56, color: Colors.grey),
        const SizedBox(height: 16),
        Text(
          'Connect to your Quark',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the address of your Quark device on your home network.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        NearbyQuarks(
          browse: widget.browse,
          onSelect: (quark) => setState(() {
            _controller.text = quark.hostAddress;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            labelText: 'Quark address',
            hintText: 'https://quark.local',
            helperText: 'Usually https://quark.local or https://192.168.x.x',
            errorText: _error,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(QuarkIcons.link_rounded),
          ),
        ),
        EmulatorLoopbackHint(controller: _controller),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _connect,
          child: _saving ? const QuarkLoader(size: 20) : const Text('Connect'),
        ),
      ],
    );
  }
}
