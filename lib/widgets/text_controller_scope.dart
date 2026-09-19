import 'package:flutter/widgets.dart';

/// Owns a [TextEditingController] for exactly as long as it is in the tree.
///
/// A dialog's future completes the moment it is popped, while the dialog is
/// still on screen playing its exit transition. A controller created beside
/// `showDialog` and disposed once that future completes is gone while its
/// `TextField` is still mounted, and anything that rebuilds the closing
/// dialog — a route pushed straight after it, as creating a doc or a sheet
/// does — uses the disposed controller and takes the overlay down with a
/// `_dependents.isEmpty` assertion (#2012, #2055). Build the dialog's content
/// inside this instead, and the controller is disposed with the dialog.
///
/// ```dart
/// QuarkWidget.showDialog<String>(
///   context,
///   builder: (dialogContext) => TextControllerScope(
///     builder: (context, controller) => QuarkWidget.alertDialog(...),
///   ),
/// );
/// ```
class TextControllerScope extends StatefulWidget {
  /// Creates a scope whose controller starts with [initialText].
  const TextControllerScope({
    required this.builder,
    this.initialText = '',
    super.key,
  });

  /// The text the controller starts with.
  final String initialText;

  /// Builds the subtree that uses the controller.
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
