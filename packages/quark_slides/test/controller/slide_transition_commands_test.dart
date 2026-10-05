import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  const fade = SlideTransitionSpec.fade();
  const push = SlideTransitionSpec(
    kind: SlideTransitionKind.push,
    direction: SlideTransitionDirection.up,
    durationMs: 800,
  );
  late SlideDocumentController doc;
  setUp(() {
    doc = SlideDocumentController(
      Presentation(
        slides: [
          const Slide(id: 'a'),
          const Slide(id: 'b'),
          const Slide(id: 'c')
        ],
      ),
    );
  });

  Slide slide(String id) => doc.presentation.slideById(id)!;

  group('setSlideTransition', () {
    test('gives one slide a transition as one undo step', () {
      doc.setSlideTransition('b', push);
      expect(slide('b').transition, push);
      expect(slide('a').transition, isNull);
      expect(doc.presentation.transitionFor(slide('b')), push);
      expect(doc.undo(), isTrue);
      expect(slide('b').transition, isNull);
      expect(doc.canUndo, isFalse);
    });

    test('null makes the slide follow the deck again', () {
      doc.applyTransitionToAll(fade);
      doc.setSlideTransition('b', push);
      doc.setSlideTransition('b', null);
      expect(slide('b').transition, isNull);
      expect(doc.presentation.transitionFor(slide('b')), fade);
    });

    test('setting the transition a slide has records no step', () {
      doc.setSlideTransition('a', null);
      expect(doc.canUndo, isFalse);
      doc.setSlideTransition('a', fade);
      doc.setSlideTransition('a', const SlideTransitionSpec.fade());
      doc.undo();
      expect(doc.canUndo, isFalse);
    });

    test('an unknown slide throws', () {
      expect(() => doc.setSlideTransition('nope', fade), throwsArgumentError);
    });

    test('a duplicated slide keeps its transition', () {
      doc.setSlideTransition('a', push);
      doc.duplicateSlide('a');
      expect(doc.presentation.slides[1].transition, push);
    });
  });

  group('applyTransitionToAll', () {
    test('sets the deck default and clears every override in one step', () {
      doc.setSlideTransition('a', push);
      doc.setSlideTransition('c', SlideTransitionSpec.none);
      doc.applyTransitionToAll(fade);
      final deck = doc.presentation;
      expect(deck.defaultTransition, fade);
      expect(deck.slides.map((s) => s.transition), everyElement(isNull));
      expect(deck.slides.map(deck.transitionFor), everyElement(fade));

      expect(doc.undo(), isTrue);
      expect(doc.presentation.defaultTransition, SlideTransitionSpec.none);
      expect(slide('a').transition, push);
      expect(slide('c').transition, SlideTransitionSpec.none);
    });

    test('a slide added afterwards plays it too', () {
      doc.applyTransitionToAll(push);
      final id = doc.addSlide();
      expect(doc.presentation.transitionFor(slide(id)), push);
    });

    test('applying what every slide already plays records no step', () {
      doc.applyTransitionToAll(SlideTransitionSpec.none);
      expect(doc.canUndo, isFalse);
    });

    test('it is redone as the same single step', () {
      doc.applyTransitionToAll(fade);
      doc.undo();
      expect(doc.redo(), isTrue);
      expect(doc.presentation.defaultTransition, fade);
    });
  });
}
