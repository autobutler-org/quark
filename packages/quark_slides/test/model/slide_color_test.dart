import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  test('an opaque color writes as #RRGGBB', () {
    expect(const SlideColor(0xFF3366FF).toHex(), '#3366FF');
  });

  test('a translucent color writes its alpha last', () {
    expect(const SlideColor(0x0A3366FF).toHex(), '#3366FF0A');
  });

  test('parse reads both forms, in either case', () {
    expect(SlideColor.parse('#3366ff'), const SlideColor(0xFF3366FF));
    expect(SlideColor.parse('#3366FF0a'), const SlideColor(0x0A3366FF));
  });

  test('parse rejects anything else', () {
    for (final bad in ['3366FF', '#36F', '#3366FFF', 'red', '#GG0000']) {
      expect(
        () => SlideColor.parse(bad),
        throwsA(isA<QslideFormatException>()),
        reason: bad,
      );
    }
  });
}
