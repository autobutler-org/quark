import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/sample_presentation.dart';

void main() {
  test('equal presentations are equal and hash alike', () {
    expect(samplePresentation(), samplePresentation());
    expect(samplePresentation().hashCode, samplePresentation().hashCode);
  });

  test('a one-field difference deep in the tree breaks equality', () {
    final deck = samplePresentation();
    final slide = deck.slides.first;
    final box = slide.elements.first as TextBox;
    final changed = deck.copyWith(
      slides: [
        slide.copyWith(
          elements: [
            box.copyWith(paragraphs: [TextParagraph.plain('Changed')]),
            ...slide.elements.skip(1),
          ],
        ),
        ...deck.slides.skip(1),
      ],
    );
    expect(changed, isNot(deck));
  });

  test('lists in the model cannot be mutated', () {
    final deck = samplePresentation();
    expect(() => deck.slides.add(const Slide(id: 'x')), throwsUnsupportedError);
  });

  test('copyWith clears a nullable field when passed null', () {
    final shape = ShapeElement(
      id: 'a',
      frame: ElementFrame(x: 0, y: 0, width: 1, height: 1),
      fill: SlideColor.black,
    );
    expect(shape.copyWith(fill: null).fill, isNull);
    expect(shape.copyWith(kind: ShapeKind.star).fill, SlideColor.black);
  });

  test('plainText joins runs and paragraphs', () {
    final box = samplePresentation().slides.first.elements.first as TextBox;
    expect(box.plainText, 'Hello, slides\n\nSecond line');
  });

  test('lookups by id', () {
    final deck = samplePresentation();
    expect(deck.indexOfSlide('s2'), 1);
    expect(deck.slideById('nope'), isNull);
    expect(deck.slides[1].elementById('e4'), isA<LineElement>());
    expect(deck.slides[1].indexOfElement('nope'), -1);
  });
}
