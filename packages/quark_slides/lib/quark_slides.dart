/// The headless presentation engine: the immutable slide model
/// (`Presentation`, `Slide`, the sealed `SlideElement` family), the
/// `.qslide` file format through `QslideCodec`, the
/// `SlideDocumentController` with its `SlideDocumentNotifier` wrapper,
/// `SlideCanvas`, which draws a slide and edits it through the controller,
/// and the rich-text editing behind its text boxes: the pure functions over
/// runs (`replaceText`, `formatParagraphs`, `textFormatOf`), `TextFormat`,
/// and the `SlideTextEditingController` a toolbar formats through; and the
/// drawing tools: `SlideCanvasTool` and the `SlideToolController` a toolbar
/// picks them through, the insertion commands, `ElementStyle`, `ImageSource`,
/// and the pure path and drag geometry behind shapes and lines; grouping
/// (`GroupElement`, `SlideTree`, the group geometry), alignment
/// (`alignFrames`, `distributeFrames`, `matchFrameSizes`), and copy and
/// paste through a `SlideClipboard` and its `SlideClipboardCodec`; and
/// themes and layouts: `SlideTheme` and the built-in `SlideThemes`, role
/// colors (`SlideColor.theme(ThemeColor.accent1)`), and the `SlideLayout`s
/// of `SlideMaster.standard` whose placeholders slides are built from; and
/// find and replace: `SlideSearch` over a presentation, its `SlideMatch`es,
/// and the controller's `replaceCurrent` and `replaceAll`.
library;

export 'src/clipboard/slide_clipboard.dart';

export 'src/canvas/slide_canvas.dart';
export 'src/canvas/slide_canvas_style.dart';
export 'src/canvas/slide_canvas_tool.dart';
export 'src/canvas/slide_element_label.dart';
export 'src/canvas/slide_fallback_theme.dart';
export 'src/canvas/slide_image_source.dart';
export 'src/canvas/slide_shape_paths.dart';
export 'src/canvas/slide_text_editing_controller.dart';
export 'src/canvas/slide_text_layout.dart';
export 'src/canvas/slide_tool_controller.dart';
export 'src/canvas/slide_tool_label.dart';
export 'src/controller/slide_document_controller.dart';
export 'src/controller/slide_document_notifier.dart';
export 'src/format/qslide_codec.dart';
export 'src/format/qslide_format_exception.dart';
export 'src/format/slide_clipboard_codec.dart';
export 'src/geometry/frame_geometry.dart';
export 'src/geometry/group_geometry.dart';
export 'src/geometry/slide_alignment.dart';
export 'src/geometry/slide_drawing.dart';
export 'src/geometry/slide_handle.dart';
export 'src/geometry/slide_snapping.dart';
export 'src/geometry/slide_tree.dart';
export 'src/geometry/slide_viewport.dart';
export 'src/layout/layout_flow.dart';
export 'src/layout/layout_placeholder.dart';
export 'src/layout/slide_layout.dart';
export 'src/layout/slide_master.dart';
export 'src/model/element_frame.dart';
export 'src/model/element_style.dart';
export 'src/model/image_source.dart';
export 'src/model/presentation.dart';
export 'src/model/rich_text.dart';
export 'src/model/slide.dart';
export 'src/model/slide_background.dart';
export 'src/model/slide_color.dart';
export 'src/model/slide_element.dart';
export 'src/model/slide_size.dart';
export 'src/model/stroke.dart';
export 'src/model/text_format.dart';
export 'src/model/text_paragraph.dart';
export 'src/model/text_run.dart';
export 'src/model/unset.dart';
export 'src/search/slide_match.dart';
export 'src/search/slide_replace.dart';
export 'src/search/slide_search.dart';
export 'src/search/slide_search_query.dart';
export 'src/theme/slide_theme.dart';
export 'src/theme/slide_themes.dart';
export 'src/theme/theme_color.dart';
export 'src/theme/theme_palette.dart';
export 'src/theme/theme_shape_style.dart';
export 'src/theme/theme_text_role.dart';
export 'src/theme/theme_text_style.dart';
