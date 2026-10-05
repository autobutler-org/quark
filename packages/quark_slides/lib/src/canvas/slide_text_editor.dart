import 'package:flutter/widgets.dart';

import '../model/rich_text.dart';
import '../theme/slide_theme.dart';
import 'slide_canvas_style.dart';
import 'slide_paragraph_field.dart';
import 'slide_text_box_view.dart';
import 'slide_text_editing_controller.dart';
import 'slide_text_layout.dart';
import 'slide_text_paragraph_view.dart';

/// The in-place editor of the text box [session] is editing: the box's
/// draft laid out exactly as `SlideTextBoxView` draws it, with each
/// paragraph's text a [SlideParagraphField].
///
/// The canvas puts it where the box's view would be, inside the scaled and
/// rotated slide, so the text being edited sits on the slide at the same
/// size and place as the text around it. Each paragraph field is keyed
/// `slide_text_paragraph_<index>`.
class SlideTextEditor extends StatelessWidget {
  /// Creates the editor of [session]'s draft.
  const SlideTextEditor({
    super.key,
    required this.session,
    required this.style,
    required this.theme,
    required this.scale,
    this.onDone,
    this.onTab,
  });

  /// The open editing session.
  final SlideTextEditingController session;

  /// Supplies the caret and selection colors.
  final SlideCanvasStyle style;

  /// The theme the slide's role colors and unset text styles resolve
  /// against: the deck's, or `slideFallbackTheme`.
  final SlideTheme theme;

  /// Screen pixels per slide unit.
  final double scale;

  /// Ends editing, on Escape.
  final VoidCallback? onDone;

  /// Moves to the next table cell — the previous with `true` — on Tab,
  /// while a cell is edited; `null` leaves Tab doing nothing.
  final ValueChanged<bool>? onTab;

  /// The [ValueKey] value of paragraph [index]'s field.
  static String keyName(int index) => 'slide_text_paragraph_$index';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final draft = session.draft;
          if (draft == null) return const SizedBox.shrink();
          final layout = SlideTextLayout.forBox(draft, theme);
          final fit = layout.shrinkScale(draft);
          session.configureFields(layout, fit);
          final paragraphs = draft.paragraphs;
          final markers = listMarkers(paragraphs);
          final fields = session.paragraphControllers.length;
          return OverflowBox(
            alignment: SlideTextBoxView.alignmentOf(draft.anchor),
            minHeight: 0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < paragraphs.length && i < fields; i++)
                  SlideTextParagraphView(
                    key: ValueKey(keyName(i)),
                    paragraph: paragraphs[i],
                    layout: layout,
                    marker: markers[i],
                    scale: fit,
                    child: SlideParagraphField(
                      session: session,
                      index: i,
                      style: layout.rootStyle(paragraphs[i], scale: fit),
                      textAlign: layout.textAlign(paragraphs[i]),
                      scale: scale,
                      cursorColor: style.selectionColor,
                      selectionColor: style.selectionColor.withValues(
                        alpha: 0.35,
                      ),
                      onDone: onDone,
                      onTab: onTab,
                    ),
                  ),
              ],
            ),
          );
        },
      );
}
