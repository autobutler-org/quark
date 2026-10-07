import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  final wide = SlideSize.widescreen;

  test('a 16:9 slide in a tall box gets letterbox bars top and bottom', () {
    final v =
        SlideViewport(viewportSize: const Size(360, 640), slideSize: wide);
    expect(v.scale, closeTo(360 / 1920, 1e-9));
    expect(v.slideRect.width, closeTo(360, 1e-9));
    expect(v.slideRect.height, closeTo(202.5, 1e-9));
    expect(v.origin, Offset(0, (640 - 202.5) / 2));
  });

  test('a 4:3 slide in a wide box gets bars at the sides, inside the padding',
      () {
    final v = SlideViewport(
      viewportSize: const Size(1280, 800),
      slideSize: SlideSize.standard,
      padding: const EdgeInsets.all(20),
    );
    expect(v.scale, closeTo(760 / 768, 1e-9));
    expect(v.origin.dy, closeTo(20, 1e-9));
    expect(v.origin.dx, closeTo((1280 - 1024 * 760 / 768) / 2, 1e-9));
  });

  test('toSlide and toView invert each other', () {
    final v = SlideViewport(
      viewportSize: const Size(1280, 800),
      slideSize: wide,
      zoom: 1.5,
      pan: const Offset(40, -30),
    );
    const p = Offset(321, 123);
    final back = v.toView(v.toSlide(p));
    expect(back.dx, closeTo(p.dx, 1e-9));
    expect(back.dy, closeTo(p.dy, 1e-9));
  });

  test('zoom multiplies the fitted scale', () {
    final fit =
        SlideViewport(viewportSize: const Size(1280, 800), slideSize: wide);
    final half = SlideViewport(
      viewportSize: const Size(1280, 800),
      slideSize: wide,
      zoom: 0.5,
    );
    expect(half.scale, closeTo(fit.scale / 2, 1e-12));
    expect(half.slideRect.center, fit.slideRect.center);
  });

  test('pan is clamped to the overflow and zero when the slide fits', () {
    final fit = SlideViewport(
      viewportSize: const Size(1280, 720),
      slideSize: wide,
      pan: const Offset(500, 500),
    );
    expect(fit.pan, Offset.zero);
    final zoomed = SlideViewport(
      viewportSize: const Size(1280, 720),
      slideSize: wide,
      zoom: 2,
      pan: const Offset(5000, -5000),
    );
    expect(zoomed.pan, const Offset(640, -360));
    expect(zoomed.slideRect.left, 0);
    expect(zoomed.slideRect.bottom, 720);
  });

  test('panForZoom keeps the focal point over the same slide point', () {
    final v =
        SlideViewport(viewportSize: const Size(1280, 720), slideSize: wide);
    const focal = Offset(1000, 200);
    final under = v.toSlide(focal);
    final zoomed = SlideViewport(
      viewportSize: const Size(1280, 720),
      slideSize: wide,
      zoom: 2,
      pan: v.panForZoom(2, focal),
    );
    final after = zoomed.toSlide(focal);
    expect(after.dx, closeTo(under.dx, 1e-9));
    expect(after.dy, closeTo(under.dy, 1e-9));
  });
}
