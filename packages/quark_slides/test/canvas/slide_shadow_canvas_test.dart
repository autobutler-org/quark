import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_slides/src/canvas/slide_shadow_painter.dart';

import '../support/canvas_harness.dart';

/// A slide `s` with a red rectangle `box` and a picture `pic`, each casting
/// [shadow], the rectangle turned by [rotation] degrees.
Presentation shadowDeck(ElementShadow shadow, {double rotation = 0}) =>
    Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            ShapeElement(
              id: 'box',
              frame: ElementFrame(
                x: 100,
                y: 100,
                width: 200,
                height: 100,
                rotation: rotation,
              ),
              fill: const SlideColor(0xFFFF0000),
              shadow: shadow,
            ),
            ImageElement(
              id: 'pic',
              frame: ElementFrame(x: 400, y: 100, width: 300, height: 200),
              source: 'a.png',
              fit: ImageFit.fill,
              shadow: shadow,
            ),
          ],
        ),
      ],
    );

/// The render object painting the element [id], its first custom paint.
RenderObject painterOf(WidgetTester tester, String id) => tester.renderObject(
  find.descendant(of: elementKey(id), matching: find.byType(CustomPaint)).first,
);

/// Whether [method] and [args] are a shadow layer tinted [color] and
/// blurred to [sigma].
bool isShadowLayer(
  Symbol method,
  List<dynamic> args,
  Color color,
  double sigma,
) {
  if (method != #saveLayer) return false;
  final paint = args[1] as Paint;
  return paint.colorFilter == ColorFilter.mode(color, BlendMode.srcIn) &&
      paint.imageFilter ==
          (sigma == 0 ? null : ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
}

/// Matches a shadow layer tinted [color] and blurred to [sigma], moved by
/// [dx] and [dy], with the silhouette, and then the element's own drawing.
PaintPattern castsShadow(Color color, double sigma, double dx, double dy) =>
    paints
      ..something((method, args) => isShadowLayer(method, args, color, sigma))
      ..translate(x: dx, y: dy)
      ..restore();

void main() {
  final shadow = ElementShadow(
    color: const SlideColor(0x7F000000),
    x: 3,
    y: 4,
    blur: 10,
  );

  group('shadowOffset', () {
    test('is the shadow offset on an element that is not turned', () {
      expect(shadowOffset(shadow, 0), const Offset(3, 4));
    });

    test('turns against the element so the shadow falls the same way', () {
      final quarter = shadowOffset(shadow, 90);
      expect(quarter.dx, closeTo(4, 1e-9));
      expect(quarter.dy, closeTo(-3, 1e-9));
      final half = shadowOffset(shadow, 180);
      expect(half.dx, closeTo(-3, 1e-9));
      expect(half.dy, closeTo(-4, 1e-9));
      // Turned back by the element's rotation, it is the slide's offset.
      final turned = shadowOffset(shadow, 30);
      final a = 30 * math.pi / 180;
      expect(
        turned.dx * math.cos(a) - turned.dy * math.sin(a),
        closeTo(3, 1e-9),
      );
      expect(
        turned.dx * math.sin(a) + turned.dy * math.cos(a),
        closeTo(4, 1e-9),
      );
    });

    test('blurs by a Gaussian of half the blur distance', () {
      expect(shadowSigma(shadow), 5);
    });
  });

  testBothViewports('the editor draws a shape shadow under the shape', (
    tester,
    size,
  ) async {
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(shadowDeck(shadow)),
      size: size,
    );
    expect(
      painterOf(tester, 'box'),
      castsShadow(const Color(0x7F000000), 5, 3, 4)
        ..path(color: const Color(0xFFFF0000)),
    );
  });

  testBothViewports('the editor draws a picture shadow behind its frame', (
    tester,
    size,
  ) async {
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(shadowDeck(shadow)),
      size: size,
    );
    expect(
      painterOf(tester, 'pic'),
      castsShadow(const Color(0x7F000000), 5, 3, 4)
        ..rect(rect: const Rect.fromLTWH(0, 0, 300, 200)),
    );
  });

  testBothViewports('a turned shape casts its shadow the slide\'s way', (
    tester,
    size,
  ) async {
    final sharp = ElementShadow(color: SlideColor.black, x: 6);
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(shadowDeck(sharp, rotation: 90)),
      size: size,
    );
    expect(
      painterOf(tester, 'box'),
      paints
        ..something((method, args) => method == #saveLayer)
        ..something((method, args) {
          if (method != #translate) return false;
          final [dx as double, dy as double] = args;
          return dx.abs() < 1e-9 && (dy + 6).abs() < 1e-9;
        }),
    );
  });

  testBothViewports('presenting draws the shadows too', (tester, size) async {
    final deck = shadowDeck(shadow);
    await pumpReadOnly(tester, deck.slides.single, deck.size, size: size);
    expect(
      painterOf(tester, 'box'),
      castsShadow(const Color(0x7F000000), 5, 3, 4),
    );
    expect(
      painterOf(tester, 'pic'),
      castsShadow(const Color(0x7F000000), 5, 3, 4),
    );
  });

  testBothViewports('a shape without a shadow paints no shadow layer', (
    tester,
    size,
  ) async {
    final deck = shadowDeck(shadow);
    final plain = (deck.slides.single.elements.first as ShapeElement).copyWith(
      shadow: null,
    );
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(
        Presentation(
          slides: [
            Slide(id: 's', elements: [plain]),
          ],
        ),
      ),
      size: size,
    );
    expect(
      painterOf(tester, 'box'),
      isNot(paints..something((method, args) => method == #saveLayer)),
    );
  });

  testBothViewports('a shadow with no blur is not blurred', (
    tester,
    size,
  ) async {
    final sharp = ElementShadow(color: SlideColor.black, x: 2, y: 2);
    await pumpCanvas(
      tester,
      SlideDocumentNotifier(shadowDeck(sharp)),
      size: size,
    );
    expect(
      painterOf(tester, 'box'),
      castsShadow(const Color(0xFF000000), 0, 2, 2),
    );
  });
}
