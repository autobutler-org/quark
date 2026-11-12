import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/quark_widget.dart';

/// Asks for the username and password a drive action needs. Pops with a map
/// of `username` and `password`, or with nothing on Cancel.
///
/// The dialog owns its text controllers, so they live until its route has
/// finished animating out (#3102).
class CredentialsDialog extends StatefulWidget {
  const CredentialsDialog({super.key});

  @override
  State<CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<CredentialsDialog> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: const Text('Authenticate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter your credentials to continue.'),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
            autofillHints: const [AutofillHints.username],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {
            'username': _usernameCtrl.text,
            'password': _passwordCtrl.text,
          }),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
