import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// The narrow viewport every widget has to survive: a small phone.
const Size narrowViewport = Size(360, 640);

/// The wide viewport: a desktop window.
const Size wideViewport = Size(1280, 800);

/// Runs [body] against both [narrowViewport] and [wideViewport].
void testBothViewports(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('$description ($label)', (tester) => body(tester, size));
  }
}

/// A 16:9 deck with one slide, `s`: a title text box, a rectangle `box`,
/// an ellipse `ball` and an image `pic`, back to front, on a background
/// image.
Presentation canvasDeck() => Presentation(
      slides: [
        Slide(
          id: 's',
          background: const SlideBackground(image: 'bg.jpg'),
          elements: [
            TextBox(
              id: 'title',
              frame: ElementFrame(x: 160, y: 80, width: 1600, height: 200),
              paragraphs: const [
                TextParagraph([
                  TextRun('Quarterly ', fontSize: 72),
                  TextRun('review', bold: true, fontSize: 72),
                ], alignment: TextAlignment.center),
              ],
            ),
            ShapeElement(
              id: 'box',
              frame: ElementFrame(x: 200, y: 400, width: 600, height: 450),
              fill: const SlideColor(0xFF3366FF),
            ),
            ShapeElement(
              id: 'ball',
              frame: ElementFrame(x: 1300, y: 450, width: 400, height: 400),
              kind: ShapeKind.ellipse,
              fill: const SlideColor(0xFFFFCC00),
            ),
            ImageElement(
              id: 'pic',
              frame: ElementFrame(x: 900, y: 900, width: 200, height: 150),
              source: 'photos/dog.jpg',
              altText: 'A dog',
              fit: ImageFit.cover,
            ),
          ],
        ),
      ],
    );

/// Hosts a [SlideCanvas] and owns its selection and zoom, as an app page
/// would.
class CanvasHarness extends StatefulWidget {
  /// Creates a harness editing slide `s` of [document].
  const CanvasHarness({
    super.key,
    required this.document,
    this.zoom = 1,
    this.imageBuilder,
    this.textEditing,
    this.tools,
    this.onPickImage,
    this.clipboard,
    this.highlights = const [],
    this.currentHighlight,
    this.tableEditing,
    this.interaction = SlideCanvasInteraction.editable,
    this.chartEditing,
  });

  final SlideDocumentNotifier document;
  final double zoom;
  final SlideImageBuilder? imageBuilder;
  final SlideTextEditingController? textEditing;
  final SlideToolController? tools;
  final ValueChanged<ElementFrame?>? onPickImage;
  final SlideClipboard? clipboard;
  final List<SlideMatch> highlights;
  final SlideMatch? currentHighlight;
  final SlideTableEditingController? tableEditing;
  final SlideCanvasInteraction interaction;
  final SlideChartEditingController? chartEditing;

  @override
  State<CanvasHarness> createState() => CanvasHarnessState();
}

class CanvasHarnessState extends State<CanvasHarness> {
  Set<String> selection = {};
  late double zoom = widget.zoom;
  late final SlideToolController tools = widget.tools ?? SlideToolController();

  /// The active tool.
  SlideCanvasTool get tool => tools.tool;

  /// Picks a tool, as a toolbar would.
  void useTool(SlideCanvasTool next) => tools.use(next);

  @override
  void dispose() {
    if (widget.tools == null) tools.dispose();
    super.dispose();
  }

  /// Sets the selection from outside the canvas, as a toolbar would.
  void select(Set<String> ids) => setState(() => selection = ids);

  @override
  Widget build(BuildContext context) => SlideCanvas(
        document: widget.document,
        slideId: 's',
        selection: selection,
        onSelectionChanged: select,
        zoom: zoom,
        onZoomChanged: (z) => setState(() => zoom = z),
        imageBuilder: widget.imageBuilder,
        textEditing: widget.textEditing,
        tools: tools,
        onPickImage: widget.onPickImage,
        clipboard: widget.clipboard,
        highlights: widget.highlights,
        currentHighlight: widget.currentHighlight,
        tableEditing: widget.tableEditing,
        interaction: widget.interaction,
        chartEditing: widget.chartEditing,
      );
}

/// Pumps a [CanvasHarness] over [document] filling a [size] screen.
Future<void> pumpCanvas(
  WidgetTester tester,
  SlideDocumentNotifier document, {
  Size size = wideViewport,
  double zoom = 1,
  SlideImageBuilder? imageBuilder,
  SlideTextEditingController? textEditing,
  SlideToolController? tools,
  ValueChanged<ElementFrame?>? onPickImage,
  SlideClipboard? clipboard,
  List<SlideMatch> highlights = const [],
  SlideMatch? currentHighlight,
  SlideTableEditingController? tableEditing,
  double textScale = 1,
  SlideCanvasInteraction interaction = SlideCanvasInteraction.editable,
  SlideChartEditingController? chartEditing,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: CanvasHarness(
          document: document,
          zoom: zoom,
          imageBuilder: imageBuilder,
          textEditing: textEditing,
          tools: tools,
          onPickImage: onPickImage,
          clipboard: clipboard,
          highlights: highlights,
          currentHighlight: currentHighlight,
          tableEditing: tableEditing,
          interaction: interaction,
          chartEditing: chartEditing,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Taps [global] twice, 100 ms apart, as a double tap.
Future<void> doubleTap(
  WidgetTester tester,
  Offset global, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  for (final ms in [0, 100]) {
    final gesture = await tester.createGesture(kind: kind);
    await gesture.down(global, timeStamp: Duration(milliseconds: ms));
    await gesture.up(timeStamp: Duration(milliseconds: ms + 20));
    await tester.pump();
  }
  await tester.pump();
}

/// The harness's state: its selection and zoom.
CanvasHarnessState harness(WidgetTester tester) =>
    tester.state<CanvasHarnessState>(find.byType(CanvasHarness));

/// The canvas's mapping between slide units and its own box, rebuilt the
/// way the canvas builds it (default padding, no pan).
SlideViewport canvasViewport(WidgetTester tester, {double zoom = 1}) =>
    SlideViewport(
      viewportSize: tester.getSize(find.byType(SlideCanvas)),
      slideSize: SlideSize.widescreen,
      zoom: zoom,
      padding: const EdgeInsets.all(24),
    );

/// The global position of the slide point [slidePoint].
Offset slideToGlobal(WidgetTester tester, Offset slidePoint) =>
    tester.getTopLeft(find.byType(SlideCanvas)) +
    canvasViewport(tester).toView(slidePoint);

/// Finds the element [id]'s widget.
Finder elementKey(String id) => find.byKey(ValueKey('slide_element_$id'));

/// Finds the handle [handle]'s widget.
Finder handleKey(SlideHandle handle) => find.byKey(ValueKey(handle.keyName));

/// The frame of element [id] on slide `s`.
ElementFrame frameOf(SlideDocumentNotifier doc, String id) =>
    doc.presentation.slideById('s')!.elementById(id)!.frame;

/// Undoes everything and returns how many steps there were.
int undoAll(SlideDocumentNotifier doc) {
  var steps = 0;
  while (doc.controller.undo()) {
    steps++;
  }
  return steps;
}
