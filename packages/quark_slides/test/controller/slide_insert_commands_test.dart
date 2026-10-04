import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

/// A 1920×1080 deck with one slide `s` holding a text box `t`, a shape
/// `box`, a line `l` and an image `pic`.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            TextBox(
              id: 't',
              frame: ElementFrame(x: 0, y: 0, width: 200, height: 50),
            ),
            ShapeElement(
              id: 'box',
              frame: ElementFrame(x: 0, y: 100, width: 200, height: 100),
              fill: SlideColor.black,
            ),
            LineElement(
              id: 'l',
              frame: ElementFrame(x: 0, y: 300, width: 200, height: 0),
            ),
            ImageElement(
              id: 'pic',
              frame: ElementFrame(x: 0, y: 400, width: 200, height: 100),
              source: 'photos/a.jpg',
            ),
          ],
        ),
      ],
    );

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(deck(), newId: () => 'n${next++}');
  });

  SlideElement element(String id) =>
      doc.presentation.slideById('s')!.elementById(id)!;

  /// Undoes everything and returns how many steps there were.
  int undoAll() {
    var steps = 0;
    while (doc.undo()) {
      steps++;
    }
    return steps;
  }

  group('insertShape', () {
    test('centers a default square on the slide, in front, as one step', () {
      final id = doc.insertShape('s', ShapeKind.star);
      final shape = element(id) as ShapeElement;
      expect(shape.kind, ShapeKind.star);
      expect(
        shape.frame,
        ElementFrame(x: 760, y: 340, width: 400, height: 400),
      );
      expect(shape.fill, SlideDocumentController.defaultShapeFill);
      expect(shape.stroke, isNull);
      expect(doc.presentation.slideById('s')!.elements.last.id, id);
      expect(undoAll(), 1);
    });

    test('takes a frame, a fill or none, a stroke and a stacking index', () {
      final frame = ElementFrame(x: 1, y: 2, width: 3, height: 4);
      final id = doc.insertShape(
        's',
        ShapeKind.ellipse,
        frame: frame,
        fill: null,
        stroke: Stroke(dash: StrokeDash.dot),
        index: 0,
      );
      final shape = element(id) as ShapeElement;
      expect(shape.frame, frame);
      expect(shape.fill, isNull);
      expect(shape.stroke!.dash, StrokeDash.dot);
      expect(doc.presentation.slideById('s')!.elements.first.id, id);
    });
  });

  group('insertLine', () {
    test('centers a default horizontal line, as one step', () {
      final id = doc.insertLine('s', endCap: LineCap.arrow);
      final line = element(id) as LineElement;
      expect(line.frame, ElementFrame(x: 760, y: 540, width: 400, height: 0));
      expect(line.endCap, LineCap.arrow);
      expect(line.startCap, LineCap.none);
      expect(line.stroke.width, SlideDocumentController.defaultLineWidth);
      expect(undoAll(), 1);
    });

    test('takes a frame and a direction', () {
      final id = doc.insertLine(
        's',
        frame: ElementFrame(x: 10, y: 10, width: 50, height: 50),
        flipped: true,
        startCap: LineCap.arrow,
      );
      final line = element(id) as LineElement;
      expect(line.flipped, isTrue);
      expect(line.startCap, LineCap.arrow);
    });
  });

  group('insertImage', () {
    test('a large picture is centered and fitted within 60% of the slide', () {
      final id = doc.insertImage(
        's',
        const QuarkFileImage('photos/dog.jpg'),
        (width: 4000, height: 3000),
        altText: 'A dog',
      );
      final image = element(id) as ImageElement;
      // 60% of 1080 is 648 tall, so 864 wide at 4:3.
      expect(image.frame.height, closeTo(648, 1e-9));
      expect(image.frame.width, closeTo(864, 1e-9));
      expect(image.frame.x, closeTo((1920 - 864) / 2, 1e-9));
      expect(image.frame.y, closeTo((1080 - 648) / 2, 1e-9));
      expect(image.source, 'photos/dog.jpg');
      expect(image.imageSource, const QuarkFileImage('photos/dog.jpg'));
      expect(image.altText, 'A dog');
      expect(undoAll(), 1);
    });

    test('a wide picture is held by the slide width', () {
      final id = doc.insertImage(
        's',
        const QuarkFileImage('pano.jpg'),
        (width: 10000, height: 1000),
      );
      final frame = element(id).frame;
      expect(frame.width, closeTo(1152, 1e-9));
      expect(frame.height, closeTo(115.2, 1e-9));
    });

    test('a small picture keeps its own size', () {
      final id = doc.insertImage(
        's',
        const UploadedAssetImage('icon7'),
        (width: 64, height: 32),
      );
      final image = element(id) as ImageElement;
      expect(
        image.frame,
        ElementFrame(x: 928, y: 524, width: 64, height: 32),
      );
      expect(image.source, 'asset:icon7');
    });

    test('a drawn box is filled as far as the aspect ratio allows', () {
      final id = doc.insertImage(
        's',
        const QuarkFileImage('a.jpg'),
        (width: 64, height: 32),
        within: ElementFrame(x: 100, y: 100, width: 400, height: 400),
      );
      expect(
        element(id).frame,
        ElementFrame(x: 100, y: 200, width: 400, height: 200),
      );
    });

    test('a size without area is refused', () {
      expect(
        () => doc.insertImage(
          's',
          const QuarkFileImage('a.jpg'),
          (width: 0, height: 10),
        ),
        throwsArgumentError,
      );
      expect(doc.canUndo, isFalse);
    });
  });

  group('styleElements', () {
    test('restyles shapes and lines as one step, skipping the rest', () {
      doc.styleElements(
        's',
        ['t', 'box', 'l', 'pic'],
        const ElementStyle(
          fill: null,
          strokeColor: SlideColor.white,
          strokeWidth: 6,
          dash: StrokeDash.dash,
          opacity: 0.5,
        ),
      );
      final shape = element('box') as ShapeElement;
      expect(shape.fill, isNull);
      expect(
        shape.stroke,
        Stroke(color: SlideColor.white, width: 6, dash: StrokeDash.dash),
      );
      expect(shape.opacity, 0.5);
      final line = element('l') as LineElement;
      expect(line.stroke.dash, StrokeDash.dash);
      expect(line.opacity, 0.5);
      expect(element('t'), deck().slides.single.elementById('t'));
      expect(element('pic'), deck().slides.single.elementById('pic'));
      expect(undoAll(), 1);
    });

    test('a field left out is left alone; null clears what can be cleared', () {
      doc.styleElements('s', ['box'], const ElementStyle(cornerRadius: 12.0));
      doc.styleElements(
        's',
        ['box'],
        const ElementStyle(kind: ShapeKind.roundedRectangle),
      );
      var shape = element('box') as ShapeElement;
      expect(shape.cornerRadius, 12);
      expect(shape.kind, ShapeKind.roundedRectangle);
      expect(shape.fill, SlideColor.black);
      doc.styleElements(
        's',
        ['box'],
        const ElementStyle(cornerRadius: null, stroke: null),
      );
      shape = element('box') as ShapeElement;
      expect(shape.cornerRadius, isNull);
      expect(shape.stroke, isNull);
    });

    test('caps apply to lines only', () {
      doc.styleElements(
        's',
        ['box', 'l'],
        const ElementStyle(startCap: LineCap.arrow, endCap: LineCap.arrow),
      );
      final line = element('l') as LineElement;
      expect((line.startCap, line.endCap), (LineCap.arrow, LineCap.arrow));
    });

    test('a change that changes nothing records no step', () {
      doc.styleElements('s', ['t', 'pic'], const ElementStyle(opacity: 0.5));
      expect(doc.canUndo, isFalse);
    });
  });

  test('elementStyleOf summarizes what the selection shares', () {
    final frame = ElementFrame(x: 0, y: 0, width: 1, height: 1);
    final a = ShapeElement(
      id: 'a',
      frame: frame,
      fill: SlideColor.black,
      stroke: Stroke(width: 3),
    );
    final b = a.copyWith(id: 'b', fill: SlideColor.white);
    final line = LineElement(id: 'l', frame: frame, stroke: Stroke(width: 3));
    final style = elementStyleOf([a, b, line]);
    expect(style.fill, unset);
    expect(style.strokeWidth, 3);
    expect(style.dash, StrokeDash.solid);
    expect(style.opacity, 1);
    expect(style.kind, ShapeKind.rectangle);
    expect(style.endCap, LineCap.none);
    expect(elementStyleOf([a]).fill, SlideColor.black);
    expect(elementStyleOf([a.copyWith(fill: null)]).fill, isNull);
    expect(elementStyleOf([a.copyWith(stroke: null)]).stroke, isNull);
    expect(elementStyleOf([a]).stroke, unset);
  });

  group('setAltText', () {
    test('sets an image description as one step', () {
      doc.setAltText('s', 'pic', 'A cat');
      expect((element('pic') as ImageElement).altText, 'A cat');
      expect(undoAll(), 1);
    });

    test('refuses an element that is not an image', () {
      expect(() => doc.setAltText('s', 'box', 'x'), throwsArgumentError);
    });
  });
}
