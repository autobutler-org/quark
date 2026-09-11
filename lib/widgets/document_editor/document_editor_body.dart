import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/document_editor/document_editor_toolbar.dart';
import 'package:quark/widgets/document_editor/document_find_bar.dart';
import 'package:quark/widgets/document_editor/document_page_frame.dart';
import 'package:quark/widgets/document_editor/document_status_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the document editor's app bar: the load state, or the
/// toolbar, find bar, page and status bar stacked over each other.
class DocumentEditorBody extends StatelessWidget {
  final bool loading;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;
  final VoidCallback onRetry;

  final QuillController controller;
  final FocusNode editorFocus;
  final ScrollController scrollController;

  /// Read-only / edit mode (#939) — the toolbar is edit-only.
  final bool isReadOnly;
  final bool showFindBar;
  final VoidCallback onToggleFindBar;
  final QuillToolbarColorPickerOnPressedCallback onPickBackgroundColor;

  /// Page brightness, chosen independently of the global theme toggle (#938).
  final bool darkPage;
  final VoidCallback onToggleDarkPage;
  final VoidCallback onEditorTap;
  final DocumentEditorKeyHandler onEditorKey;

  final ValueListenable<int> wordCount;
  final bool dirty;

  const DocumentEditorBody({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.controller,
    required this.editorFocus,
    required this.scrollController,
    required this.isReadOnly,
    required this.showFindBar,
    required this.onToggleFindBar,
    required this.onPickBackgroundColor,
    required this.darkPage,
    required this.onToggleDarkPage,
    required this.onEditorTap,
    required this.onEditorKey,
    required this.wordCount,
    required this.dirty,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(QuarkIcons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              Errors.message(error, 'load the document'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (!isReadOnly)
          DocumentEditorToolbar(
            controller: controller,
            onPickBackgroundColor: onPickBackgroundColor,
          ),
        // Find works in view mode too — the toolbar above is edit-only, the
        // find bar is not.
        if (showFindBar)
          DocumentFindBar(controller: controller, onClose: onToggleFindBar),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Expanded(
                    child: DocumentPageFrame(
                      controller: controller,
                      editorFocus: editorFocus,
                      scrollController: scrollController,
                      darkPage: darkPage,
                      isReadOnly: isReadOnly,
                      onTap: onEditorTap,
                      onKeyPressed: onEditorKey,
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: wordCount,
                    builder: (context, count, _) => DocumentStatusBar(
                      darkPage: darkPage,
                      onToggleDarkPage: onToggleDarkPage,
                      wordCount: count,
                      isReadOnly: isReadOnly,
                      dirty: dirty,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
