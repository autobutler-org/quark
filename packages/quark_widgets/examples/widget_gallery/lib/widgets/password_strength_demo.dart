import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Types into a real field so the bar animates, which a static example cannot
/// show.
class PasswordStrengthDemo extends StatefulWidget {
  /// Creates the demo field and bar.
  const PasswordStrengthDemo({super.key});

  @override
  State<PasswordStrengthDemo> createState() => _PasswordStrengthDemoState();
}

class _PasswordStrengthDemoState extends State<PasswordStrengthDemo> {
  final _controller = TextEditingController(text: 'hunter2');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(labelText: 'Password'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          PasswordStrengthBar(password: _controller.text),
        ],
      ),
    );
  }
}
