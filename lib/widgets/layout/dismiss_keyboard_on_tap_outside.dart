import 'package:flutter/widgets.dart';

/// Closes the on-screen keyboard when a tap lands outside the focused text
/// field, on a phone as everywhere else (#4051).
///
/// Flutter only drops a field's focus on a touch outside it on the web; on
/// native iOS and Android the keyboard stayed up until something else took
/// focus. This overrides that one action for everything under it, so the app
/// wraps its navigator in it once. A widget that should count as part of the
/// field, like a chat composer's send button, sits in a `TextFieldTapRegion`.
class DismissKeyboardOnTapOutside extends StatelessWidget {
  const DismissKeyboardOnTapOutside({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) => intent.focusNode.unfocus(),
          ),
    },
    child: child,
  );
}
