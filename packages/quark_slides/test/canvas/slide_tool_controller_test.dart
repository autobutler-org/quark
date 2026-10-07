import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  group('SlideToolController', () {
    test('starts on select, or on the tool it is given', () {
      expect(SlideToolController().tool, SlideCanvasTool.select);
      expect(SlideToolController().mode, SlideToolMode.select);
      expect(
        SlideToolController(SlideCanvasTool.line).mode,
        SlideToolMode.line,
      );
    });

    test('use switches tools and notifies only on a change', () {
      final tools = SlideToolController();
      addTearDown(tools.dispose);
      var notified = 0;
      tools.addListener(() => notified++);
      tools.use(const SlideCanvasTool.shape(ShapeKind.star));
      expect(tools.mode, SlideToolMode.shape);
      expect(tools.tool.shapeKind, ShapeKind.star);
      expect(notified, 1);
      tools.use(const SlideCanvasTool.shape(ShapeKind.star));
      expect(notified, 1);
      tools.use(const SlideCanvasTool.shape(ShapeKind.ellipse));
      expect(notified, 2);
      tools.use(SlideCanvasTool.arrowLine);
      expect(tools.tool.arrow, isTrue);
      expect(notified, 3);
      tools.reset();
      expect(tools.tool, SlideCanvasTool.select);
      expect(notified, 4);
      tools.reset();
      expect(notified, 4);
    });
  });

  group('SlideCanvasTool', () {
    test('compares by value', () {
      expect(
        const SlideCanvasTool.shape(ShapeKind.star),
        const SlideCanvasTool.shape(ShapeKind.star),
      );
      expect(
        const SlideCanvasTool.shape(ShapeKind.star).hashCode,
        const SlideCanvasTool.shape(ShapeKind.star).hashCode,
      );
      expect(SlideCanvasTool.line, isNot(SlideCanvasTool.arrowLine));
    });

    test('every tool but select draws', () {
      expect(SlideCanvasTool.select.draws, isFalse);
      for (final tool in [
        SlideCanvasTool.text,
        SlideCanvasTool.line,
        SlideCanvasTool.arrowLine,
        SlideCanvasTool.image,
        const SlideCanvasTool.shape(ShapeKind.triangle),
      ]) {
        expect(tool.draws, isTrue, reason: '$tool');
      }
    });

    test('toString names the tool', () {
      expect(
        '${const SlideCanvasTool.shape(ShapeKind.star)}',
        'SlideCanvasTool.shape(star)',
      );
      expect('${SlideCanvasTool.arrowLine}', 'SlideCanvasTool.arrowLine');
      expect('${SlideCanvasTool.image}', 'SlideCanvasTool.image');
    });
  });

  test('defaultSlideToolLabel names the insertion', () {
    expect(defaultSlideToolLabel(SlideCanvasTool.select), 'Select');
    expect(defaultSlideToolLabel(SlideCanvasTool.text), 'Insert text box');
    expect(
      defaultSlideToolLabel(const SlideCanvasTool.shape(ShapeKind.arrow)),
      'Insert right arrow',
    );
    expect(defaultSlideToolLabel(SlideCanvasTool.line), 'Insert line');
    expect(defaultSlideToolLabel(SlideCanvasTool.arrowLine), 'Insert arrow');
    expect(defaultSlideToolLabel(SlideCanvasTool.image), 'Insert image');
    for (final kind in ShapeKind.values) {
      expect(shapeKindName(kind), isNotEmpty);
    }
  });
}
