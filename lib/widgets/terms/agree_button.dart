import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

/// The "I Agree" button.
///
/// Stateful only to hold the in-flight state: accepting terms resolves the
/// next route, which asks the Quark whether it has been set up, and that is a
/// network round-trip the user should see happening.
class AgreeButton extends StatefulWidget {
  const AgreeButton({super.key});

  @override
  State<AgreeButton> createState() => _AgreeButtonState();
}

class _AgreeButtonState extends State<AgreeButton> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    await AppSettings.instance.acceptTerms();
    // Resolved here rather than by going to /files and leaving it to the
    // router's redirect: that redirect silently did nothing when the status
    // call failed, stranding the user on a signed-out file browser (#1624).
    final destination = await destinationAfterAcceptingTerms();
    if (!mounted) return;
    context.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _accepting ? null : _accept,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _accepting
            ? const QuarkLoader(size: 20)
            : const Text('I Agree', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
