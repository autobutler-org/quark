import 'package:quark_slides/quark_slides.dart';

/// A presentation that uses every element type and every optional field, so
/// that a round trip through `.qslide` exercises the whole model.
/// `test/fixtures/sample.qslide` is its golden encoding.
Presentation samplePresentation() => Presentation(
      title: 'Sample deck',
      theme: 'themes/default',
      slides: [
        Slide(
          id: 's1',
          background: const SlideBackground(color: SlideColor(0xFF102030)),
          notes: 'Welcome everyone.',
          elements: [
            TextBox(
              id: 'e1',
              frame: ElementFrame(x: 160, y: 120, width: 1600, height: 240),
              paragraphs: const [
                TextParagraph([
                  TextRun('Hello, ', fontSize: 72),
                  TextRun(
                    'slides',
                    bold: true,
                    italic: true,
                    underline: true,
                    strikethrough: true,
                    fontSize: 72,
                    fontFamily: 'Inter',
                    color: SlideColor(0xFFFFCC00),
                  ),
                ], alignment: TextAlignment.center),
                TextParagraph([]),
                TextParagraph(
                  [TextRun('Second line')],
                  lineSpacing: 1.5,
                  list: TextListStyle.numbered,
                ),
              ],
              anchor: TextAnchor.middle,
              autoFit: TextAutoFit.shrink,
              placeholder: 'Click to add title',
            ),
            ShapeElement(
              id: 'e2',
              frame: ElementFrame(
                x: 100.5,
                y: 600,
                width: 400,
                height: 300,
                rotation: 15,
              ),
              kind: ShapeKind.ellipse,
              fill: const SlideColor(0x803366FF),
              stroke: Stroke(
                color: SlideColor.white,
                width: 4,
                dash: StrokeDash.dashDot,
              ),
              opacity: 0.75,
            ),
            ShapeElement(
              id: 'e6',
              frame: ElementFrame(x: 1500, y: 700, width: 300, height: 200),
              kind: ShapeKind.roundedRectangle,
              fill: SlideColor.white,
              cornerRadius: 24,
            ),
            ImageElement(
              id: 'e7',
              frame: ElementFrame(x: 1500, y: 100, width: 200, height: 100),
              source: 'asset:logo-1',
            ),
          ],
        ),
        Slide(
          id: 's2',
          background: const SlideBackground(image: 'photos/sky.jpg'),
          elements: [
            ImageElement(
              id: 'e3',
              frame: ElementFrame(x: 0, y: 0, width: 960, height: 1080),
              source: 'photos/dog.jpg',
              altText: 'A dog on a beach',
              fit: ImageFit.cover,
            ),
            LineElement(
              id: 'e4',
              frame: ElementFrame(x: 1000, y: 200, width: 600, height: 0),
              stroke: Stroke(color: const SlideColor(0xFFFF0000), width: 3),
              flipped: true,
              startCap: LineCap.none,
              endCap: LineCap.arrow,
              opacity: 0.5,
            ),
            ShapeElement(
              id: 'e5',
              frame: ElementFrame(x: 1200, y: 700, width: 200, height: 200),
            ),
          ],
        ),
        const Slide(id: 's3'),
      ],
    );
