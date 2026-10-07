import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The bar button that opens the slide editor's find bar, lit while it is
/// open: Find and replace, Ctrl or Cmd F.
///
/// Key prefixes: `slide_find_open`.
class SlideFindButton extends StatelessWidget {
  /// Creates the button; [isOpen] lights it.
  const SlideFindButton({
    required this.isOpen,
    required this.onPressed,
    super.key,
  });

  /// Whether the find bar is showing.
  final bool isOpen;

  /// Opens the find bar, or closes it when it is open.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => QuarkBarIconButton(
    key: const ValueKey('slide_find_open'),
    icon: QuarkIcons.search_rounded,
    tooltip: 'Find and replace',
    selected: isOpen,
    onPressed: onPressed,
  );
}
