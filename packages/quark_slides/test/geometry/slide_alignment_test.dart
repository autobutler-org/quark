import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

ElementFrame f(double x, double y, double w, double h, [double r = 0]) =>
    ElementFrame(x: x, y: y, width: w, height: h, rotation: r);

void main() {
  final frames = {
    'a': f(100, 100, 100, 50),
    'b': f(300, 250, 200, 100),
    'c': f(150, 500, 50, 50),
  };
  const slide = (left: 0.0, top: 0.0, right: 1920.0, bottom: 1080.0);

  group('alignFrames', () {
    test('left, center and right line up on the box around them all', () {
      expect(alignFrames(frames, ElementAlignment.left).values.map((e) => e.x),
          [100, 100, 100]);
      expect(
          alignFrames(frames, ElementAlignment.right)
              .values
              .map((e) => e.x + e.width),
          [500, 500, 500]);
      expect(
          alignFrames(frames, ElementAlignment.center)
              .values
              .map((e) => e.x + e.width / 2),
          [300, 300, 300]);
    });

    test('top, middle and bottom only move vertically', () {
      final top = alignFrames(frames, ElementAlignment.top);
      expect(top.values.map((e) => e.y), [100, 100, 100]);
      expect(top.values.map((e) => e.x), [100, 300, 150]);
      expect(
          alignFrames(frames, ElementAlignment.bottom)
              .values
              .map((e) => e.y + e.height),
          [550, 550, 550]);
      expect(
          alignFrames(frames, ElementAlignment.middle)
              .values
              .map((e) => e.y + e.height / 2),
          [325, 325, 325]);
    });

    test('aligns to the slide when given it', () {
      final one = alignFrames({'a': frames['a']!}, ElementAlignment.center,
          within: slide);
      expect(one['a'], f(910, 100, 100, 50));
      final bottom = alignFrames({'a': frames['a']!}, ElementAlignment.bottom,
          within: slide);
      expect(bottom['a']!.y, 1030);
    });

    test('a rotated element lines up by what shows, and keeps its turn', () {
      final turned = alignFrames({
        'r': f(0, 0, 100, 20, 90),
        'a': f(200, 0, 50, 50),
      }, ElementAlignment.left);
      // The upright bounds of the turned bar start at x 40.
      expect(turned['a']!.x, closeTo(40, 1e-9));
      expect(turned['r']!.rotation, 90);
    });

    test('nothing to align gives nothing', () {
      expect(alignFrames(const {}, ElementAlignment.left), isEmpty);
    });
  });

  group('distributeFrames', () {
    test('leaves the outermost in place and evens the gaps between', () {
      final spread = distributeFrames({
        'a': f(0, 0, 100, 10),
        'b': f(150, 0, 100, 10),
        'c': f(500, 0, 100, 10),
      }, DistributeAxis.horizontal);
      expect(spread['a']!.x, 0);
      expect(spread['b']!.x, 250);
      expect(spread['c']!.x, 500);
    });

    test('orders by position, not by key, and returns keys as given', () {
      final spread = distributeFrames({
        'c': f(0, 600, 10, 100),
        'a': f(0, 0, 10, 100),
        'b': f(0, 120, 10, 100),
      }, DistributeAxis.vertical);
      expect(spread.keys, ['c', 'a', 'b']);
      expect(spread['b']!.y, 300);
      expect(spread['c']!.y, 600);
    });

    test('fewer than three come back unchanged', () {
      final two = {'a': f(0, 0, 10, 10), 'b': f(50, 0, 10, 10)};
      expect(distributeFrames(two, DistributeAxis.horizontal), two);
    });

    test('across the slide the ends meet its edges', () {
      final spread = distributeFrames({
        'a': f(500, 0, 100, 10),
        'b': f(700, 0, 100, 10),
      }, DistributeAxis.horizontal, within: slide);
      expect(spread['a']!.x, 0);
      expect(spread['b']!.x, 1820);
    });
  });

  group('matchFrameSizes', () {
    test('matches the largest by default, keeping top-left corners', () {
      final matched = matchFrameSizes(frames, SizeMatch.both);
      for (final frame in matched.values) {
        expect((frame.width, frame.height), (200, 100));
      }
      expect(matched['a']!.x, 100);
      expect(matched['c']!.y, 500);
    });

    test('matches one side to a chosen reference', () {
      final widths = matchFrameSizes(frames, SizeMatch.width, reference: 'c');
      expect(widths.values.map((e) => e.width), [50, 50, 50]);
      expect(widths['b']!.height, 100);
      final heights = matchFrameSizes(frames, SizeMatch.height, reference: 'a');
      expect(heights.values.map((e) => e.height), [50, 50, 50]);
      expect(heights['b']!.width, 200);
    });

    test('an unknown reference is refused', () {
      expect(() => matchFrameSizes(frames, SizeMatch.both, reference: 'z'),
          throwsArgumentError);
    });
  });
}
