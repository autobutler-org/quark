import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';

/// The "I Agree" button.
///
/// Stateful only to hold the in-flight state: accepting terms resolves the
/// next route, which asks the Quark whether it has been set up, and that is a
/// network round-trip the user should see happening. While it runs, the
/// button stays filled in its primary color and shows a spinner beside
/// "Continuing…", and it ignores taps so a second one cannot start another
/// accept.
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
    // Keep [onPressed] set so the button does not switch to the disabled gray.
    // [AbsorbPointer] is what makes the second tap a no-op: an empty callback
    // would still look tappable and a screen reader could still activate it.
    return AbsorbPointer(
      absorbing: _accepting,
      child: FilledButton(
        onPressed: _accept,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _accepting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  spacing: QuarkTokens.of(context).spacingSm,
                  children: const [
                    QuarkLoader(size: 20),
                    Text('Continuing…', style: TextStyle(fontSize: 16)),
                  ],
                )
              : const Text('I Agree', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
