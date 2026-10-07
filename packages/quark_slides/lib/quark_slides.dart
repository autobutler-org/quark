/// The headless presentation engine: the immutable slide model
/// (`Presentation`, `Slide`, the sealed `SlideElement` family), the
/// `.qslide` file format through `QslideCodec`, the
/// `SlideDocumentController` with its `SlideDocumentNotifier` wrapper, and
/// `SlideCanvas`, which draws a slide and edits it through the controller.
library;

export 'src/canvas/slide_canvas.dart';
export 'src/canvas/slide_canvas_style.dart';
export 'src/canvas/slide_element_label.dart';
export 'src/canvas/slide_image_source.dart';
export 'src/controller/slide_document_controller.dart';
export 'src/controller/slide_document_notifier.dart';
export 'src/format/qslide_codec.dart';
export 'src/format/qslide_format_exception.dart';
export 'src/geometry/frame_geometry.dart';
export 'src/geometry/slide_handle.dart';
export 'src/geometry/slide_snapping.dart';
export 'src/geometry/slide_viewport.dart';
export 'src/model/element_frame.dart';
export 'src/model/presentation.dart';
export 'src/model/slide.dart';
export 'src/model/slide_background.dart';
export 'src/model/slide_color.dart';
export 'src/model/slide_element.dart';
export 'src/model/slide_size.dart';
export 'src/model/stroke.dart';
export 'src/model/text_paragraph.dart';
export 'src/model/text_run.dart';
