import 'package:flutter/material.dart';
import 'package:quark/utils/hostname_rules.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The device name field (#2344): the Quark's hostname in a text field, a
/// Rename button, and the `.local` name it answers to on the network.
///
/// Data in, callbacks out: it holds only the text being typed. The name is
/// checked against [validateHostname] before [onSubmit] is called, so a name
/// the Quark would refuse never leaves the field.
///
/// Keys: `hostname_field` (the text field), `hostname_save` (the Rename
/// button), `hostname_address` (the line naming the `.local` address) and
/// `hostname_renamed` (the notice after a rename).
///
/// ```dart
/// HostnameField(
///   hostname: status.hostname,
///   advertisedHostname: status.advertisedHostname,
///   isWorking: controller.isWorking,
///   error: controller.error,
///   renamedTo: controller.renamedTo,
///   reopenAddress: controller.reopenAddress,
///   onSubmit: controller.rename,
/// )
/// ```
class HostnameField extends StatefulWidget {
  /// Creates the field.
  const HostnameField({
    required this.hostname,
    required this.onSubmit,
    this.advertisedHostname = '',
    this.isWorking = false,
    this.error,
    this.renamedTo,
    this.reopenAddress,
    super.key,
  });

  /// What the Quark is called now. The field starts with it, and takes it
  /// again whenever it changes.
  final String hostname;

  /// The name the Quark answers to on the network, without `.local`; empty
  /// when it is [hostname]. It differs when another device already had the
  /// name.
  final String advertisedHostname;

  /// Whether a rename is in flight: the button shows a loader and is
  /// disabled.
  final bool isWorking;

  /// Copy for the last failed rename, shown under the button; null shows
  /// nothing.
  final String? error;

  /// The `.local` name the Quark moved to, such as `kitchen.local`, shown as
  /// a notice after a rename; null shows nothing.
  final String? renamedTo;

  /// The address to open to keep using the Quark, such as
  /// `https://kitchen.local`, added to the notice when the page itself was
  /// loaded from the old name; null adds nothing.
  final String? reopenAddress;

  /// Called with the trimmed name when the user asks for a rename and the
  /// name passes [validateHostname].
  final ValueChanged<String> onSubmit;

  @override
  State<HostnameField> createState() => _HostnameFieldState();
}

class _HostnameFieldState extends State<HostnameField> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _text = TextEditingController(
    text: widget.hostname,
  );

  @override
  void didUpdateWidget(HostnameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostname != widget.hostname) _text.text = widget.hostname;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _text.text.trim();
    if (widget.isWorking || name == widget.hostname) return;
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = widget.error;
    final renamedTo = widget.renamedTo;
    final reopenAddress = widget.reopenAddress;
    final taken =
        widget.advertisedHostname.isNotEmpty &&
        widget.advertisedHostname != widget.hostname;
    final address =
        '${taken ? widget.advertisedHostname : widget.hostname}.local';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A form of one field, so the button can validate it by a key that
        // leaves the field its own.
        Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('hostname_field'),
            controller: _text,
            decoration: const InputDecoration(
              labelText: 'Device name',
              helperText: hostnameHint,
              helperMaxLines: 2,
              errorMaxLines: 3,
              border: OutlineInputBorder(),
              prefixIcon: Icon(QuarkIcons.label_outline),
            ),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateHostname,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          taken
              ? 'On your network as $address, because another device '
                    'already had the name ${widget.hostname}.'
              : 'On your network as $address',
          key: const ValueKey('hostname_address'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => FilledButton(
            key: const ValueKey('hostname_save'),
            onPressed: widget.isWorking || _text.text.trim() == widget.hostname
                ? null
                : _submit,
            child: widget.isWorking
                ? const QuarkLoader(size: 20)
                : const Text('Rename'),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: error),
        ],
        if (renamedTo != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              reopenAddress == null
                  ? 'This Quark is now at $renamedTo.'
                  : 'This Quark is now at $renamedTo. Open $reopenAddress '
                        'to keep using it.',
              key: const ValueKey('hostname_renamed'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}
