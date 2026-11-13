import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:quark_icons/quark_icons.dart';

/// Inline find bar for the document editor.
///
/// [QuillToolbarSearchDialog] owns the search itself (matching, hit list,
/// selection), but its default chrome is a [Dialog] whose close button calls
/// `Navigator.pop()` — which pops the editor route when the widget is rendered
/// inline instead of in a dialog. `childBuilder` swaps that chrome for this
/// strip, so closing the bar closes the bar (#1046).
class DocumentFindBar extends StatefulWidget {
  final QuillController controller;
  final VoidCallback onClose;

  const DocumentFindBar({
    required this.controller,
    required this.onClose,
    super.key,
  });

  @override
  State<DocumentFindBar> createState() => _DocumentFindBarState();
}

class _DocumentFindBarState extends State<DocumentFindBar> {
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'find field');

  @override
  void initState() {
    super.initState();
    // `autofocus` is a no-op when something in the scope already holds focus,
    // which is the case when the bar is opened with Ctrl/Cmd+F from inside the
    // editor. Take focus outright once the field is in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: QuillToolbarSearchDialog(
        controller: widget.controller,
        childBuilder: (options) {
          final hits = options.offsets?.length ?? 0;
          final hasHits = hits > 0;
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: options.textEditingController,
                  focusNode: _fieldFocus,
                  autofocus: true,
                  onChanged: options.onTextChanged,
                  onEditingComplete: options.onEditingComplete,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Find in document',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    suffixText: options.text.isEmpty
                        ? null
                        : '${hasHits ? options.index + 1 : 0}/$hits',
                    suffixStyle: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(QuarkIcons.keyboard_arrow_up_rounded),
                tooltip: 'Previous match',
                onPressed: hasHits ? options.moveToPrevious : null,
              ),
              IconButton(
                icon: const Icon(QuarkIcons.expand_more),
                tooltip: 'Next match',
                onPressed: hasHits ? options.moveToNext : null,
              ),
              IconButton(
                icon: const Icon(QuarkIcons.close),
                tooltip: 'Close find bar (Esc)',
                onPressed: widget.onClose,
              ),
            ],
          );
        },
      ),
    );
  }
}
