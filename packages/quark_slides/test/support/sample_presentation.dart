import 'package:quark_slides/quark_slides.dart';

/// A presentation that uses every element type — groups nested in groups
/// among them — and every optional field, a theme, a layout and role
/// colors and transitions among them, so that a round trip through `.qslide` exercises the
/// whole model. `test/fixtures/sample.qslide` is its golden encoding.
Presentation samplePresentation() => Presentation(
      title: 'Sample deck',
      theme: sampleTheme(),
      defaultTransition: const SlideTransitionSpec.fade(durationMs: 700),
      slides: [
        ...legacySamplePresentation().slides,
        Slide(
          id: 's4',
          layoutId: SlideLayout.titleAndContent.id,
          transition: const SlideTransitionSpec(
            kind: SlideTransitionKind.wipe,
            direction: SlideTransitionDirection.right,
            durationMs: 1200,
          ),
          elements: [
            TextBox(
              id: 'e13',
              frame: ElementFrame(x: 115.2, y: 54, width: 1689.6, height: 162),
              paragraphs: const [
                TextParagraph([
                  TextRun(
                    'Agenda',
                    color: SlideColor.theme(ThemeColor.accent2),
                  ),
                ]),
              ],
              anchor: TextAnchor.middle,
              autoFit: TextAutoFit.shrink,
              placeholder: 'Click to add title',
              slot: 'title',
              textRole: ThemeTextRole.title,
            ),
            TextBox(
              id: 'e14',
              frame: ElementFrame(
                  x: 115.2, y: 259.2, width: 1689.6, height: 734.4),
              paragraphs: const [TextParagraph([])],
              autoFit: TextAutoFit.shrink,
              placeholder: 'Click to add text',
              slot: 'body',
            ),
            ShapeElement(
              id: 'e15',
              frame: ElementFrame(x: 1500, y: 800, width: 200, height: 200),
              fill: const SlideColor.theme(ThemeColor.accent1),
              stroke: Stroke(color: const SlideColor.theme(ThemeColor.text)),
            ),
          ],
        ),
      ],
    );

/// A theme that sets every field, for [samplePresentation].
SlideTheme sampleTheme() => SlideThemes.warm.copyWith(
      id: 'sample',
      name: 'Sample',
      bodyFont: 'Inter',
      shapes: ThemeShapeStyle(
        stroke: Stroke(color: const SlideColor.theme(ThemeColor.accent2)),
      ),
    );

/// What `test/fixtures/v1_sample.qslide`, the sample deck as schema version
/// 1 wrote it, reads as: its theme reference named no built-in theme, so
/// the deck has none, and its slides are blank-layout.
Presentation legacySamplePresentation() => Presentation(
      title: 'Sample deck',
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
            GroupElement(
              id: 'e8',
              frame: ElementFrame(
                x: 100,
                y: 100,
                width: 600,
                height: 400,
                rotation: 30,
              ),
              children: [
                TextBox(
                  id: 'e9',
                  frame: ElementFrame(x: 0, y: 0, width: 600, height: 100),
                  paragraphs: const [
                    TextParagraph([TextRun('Grouped')]),
                  ],
                ),
                GroupElement(
                  id: 'e10',
                  frame: ElementFrame(x: 0, y: 200, width: 400, height: 200),
                  children: [
                    ShapeElement(
                      id: 'e11',
                      frame: ElementFrame(x: 0, y: 0, width: 200, height: 200),
                      kind: ShapeKind.star,
                    ),
                    ImageElement(
                      id: 'e12',
                      frame:
                          ElementFrame(x: 200, y: 0, width: 200, height: 200),
                      source: 'photos/cat.jpg',
                    ),
                  ],
                ),
              ],
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
