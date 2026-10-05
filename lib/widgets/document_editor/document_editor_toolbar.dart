import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The formatting toolbar shown above the document in edit mode.
///
/// Always one row high: on a viewport too narrow for every button it scrolls
/// sideways inside a [QuarkToolbarScroller] rather than wrapping (#2770).
///
/// The indent pair reads decrease, then increase, keyed
/// `document_editor_indent_decrease` and `document_editor_indent_increase`.
class DocumentEditorToolbar extends StatelessWidget {
  final QuillController controller;

  /// Replaces Quill's own color picker for the background/highlight button.
  final QuillToolbarColorPickerOnPressedCallback onPickBackgroundColor;

  const DocumentEditorToolbar({
    required this.controller,
    required this.onPickBackgroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final toolbarTheme = theme.copyWith(
      colorScheme: cs.copyWith(
        onSurface: cs.onSurface,
        surface: cs.surfaceContainer,
        surfaceContainerLow: cs.surfaceContainer,
        surfaceContainer: cs.surfaceContainer,
      ),
      iconTheme: IconThemeData(color: cs.onSurface, size: 16),
      textTheme: theme.textTheme.apply(
        bodyColor: cs.onSurface,
        displayColor: cs.onSurface,
      ),
    );

    final baseOptions = QuillToolbarBaseButtonOptions(
      iconTheme: QuillIconTheme(
        iconButtonUnselectedData: IconButtonData(
          color: cs.onSurface,
          style: IconButton.styleFrom(
            backgroundColor: cs.onSurface.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        iconButtonSelectedData: IconButtonData(
          style: IconButton.styleFrom(
            foregroundColor: cs.onPrimary,
            backgroundColor: cs.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );

    // flutter_quill hardcodes increase indent before decrease, and
    // `showIndent` is one switch for both. Its two slots stay where they are,
    // beside the list and quote buttons, and each draws the other's button:
    // decrease first, then increase, the order every other document editor
    // uses (#2463).
    QuillToolbarIndentButtonOptions indentSlot({required bool isIncrease}) =>
        QuillToolbarIndentButtonOptions(
          // Untyped on purpose: flutter_quill's resolver calls this through
          // `(dynamic, dynamic) => Widget`, which a typed closure is not.
          childBuilder: (dynamic _, dynamic _) => QuillToolbarIndentButton(
            key: ValueKey(
              isIncrease
                  ? 'document_editor_indent_increase'
                  : 'document_editor_indent_decrease',
            ),
            controller: controller,
            isIncrease: isIncrease,
            baseOptions: baseOptions,
          ),
        );

    return Theme(
      data: toolbarTheme,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(bottom: BorderSide(color: cs.outline)),
        ),
        // Centered while every button fits. Quill lays its buttons out in a
        // `Wrap`, which the scroller's unbounded width holds to one line.
        alignment: Alignment.center,
        child: QuarkToolbarScroller(
          child: QuillSimpleToolbar(
            controller: controller,
            config: QuillSimpleToolbarConfig(
              toolbarIconAlignment: WrapAlignment.center,
              buttonOptions: QuillSimpleToolbarButtonOptions(
                base: baseOptions,
                indentIncrease: indentSlot(isIncrease: false),
                indentDecrease: indentSlot(isIncrease: true),
                selectHeaderStyleDropdownButton:
                    QuillToolbarSelectHeaderStyleDropdownButtonOptions(
                      textStyle: TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                backgroundColor: QuillToolbarColorButtonOptions(
                  customOnPressedCallback: onPickBackgroundColor,
                ),
              ),
              showFontFamily: false,
              showFontSize: false,
              showInlineCode: true,
              showCodeBlock: true,
              showQuote: true,
              showLink: false,
              showSearchButton: false,
              showSubscript: false,
              showSuperscript: false,
            ),
          ),
        ),
      ),
    );
  }
}
