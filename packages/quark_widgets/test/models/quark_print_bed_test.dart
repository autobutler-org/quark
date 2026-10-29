import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// `QuarkPrintBed.fits` (#3228).
void main() {
  const bed = QuarkPrintBed(
    id: 'test',
    name: 'Test',
    width: 250,
    depth: 210,
    height: 220,
  );

  test('a box inside the bed fits', () {
    expect(bed.fits(width: 250, depth: 210, height: 220), isTrue);
  });

  test('a box that fits turned a quarter fits', () {
    expect(bed.fits(width: 200, depth: 240, height: 10), isTrue);
  });

  test('a box too wide, too deep or too tall does not fit', () {
    expect(bed.fits(width: 251, depth: 10, height: 10), isFalse);
    expect(bed.fits(width: 220, depth: 220, height: 10), isFalse);
    expect(bed.fits(width: 10, depth: 10, height: 221), isFalse);
  });

  test('the common beds have distinct ids', () {
    final ids = QuarkPrintBed.common.map((bed) => bed.id).toSet();
    expect(ids, hasLength(QuarkPrintBed.common.length));
  });
}
