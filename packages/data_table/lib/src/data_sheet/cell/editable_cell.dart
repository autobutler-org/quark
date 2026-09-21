import 'package:flutter/material.dart'
    show
        StatelessWidget,
        Widget,
        BuildContext,
        TextEditingController,
        VoidCallback,
        PointerDownEvent,
        InputDecoration,
        InputBorder,
        EdgeInsets,
        TextAlignVertical,
        TextField;

/// The text field shown in a cell while it is being edited.
class EditableCell extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmitted;
  final VoidCallback onEditingComplete;
  final void Function(PointerDownEvent) onTapOutside;

  const EditableCell({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onEditingComplete,
    required this.onTapOutside,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: true,
      controller: controller,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: false,
        filled: false,
      ),
      textAlignVertical: TextAlignVertical.center,
      expands: true,
      maxLines: null,
      minLines: null,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
    );
  }
}
