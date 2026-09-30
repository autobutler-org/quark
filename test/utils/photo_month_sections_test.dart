import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/photo_month_sections.dart';

/// #979: the photo grid's month headers come from runs of consecutive dates,
/// so the headers follow whatever order the grid is in.
void main() {
  List<(String, int)> runs(List<DateTime?> dates) => [
    for (final s in photoMonthSections(dates)) (s.label, s.count),
  ];

  test('nothing in, nothing out', () {
    expect(photoMonthSections(const []), isEmpty);
  });

  test('groups consecutive photos from the same month', () {
    expect(
      runs([
        DateTime(2025, 3, 30),
        DateTime(2025, 3, 1),
        DateTime(2025, 2, 14),
        DateTime(2024, 12, 25),
        DateTime(2024, 12, 1),
      ]),
      [('March 2025', 2), ('February 2025', 1), ('December 2024', 2)],
    );
  });

  test('the same month in two years is two runs', () {
    expect(runs([DateTime(2025, 3), DateTime(2024, 3)]), [
      ('March 2025', 1),
      ('March 2024', 1),
    ]);
  });

  test('works in ascending order too', () {
    expect(
      runs([DateTime(2024, 1, 2), DateTime(2024, 1, 9), DateTime(2024, 2)]),
      [('January 2024', 2), ('February 2024', 1)],
    );
  });

  test('a month that comes around again opens a new run, with its own id', () {
    final sections = photoMonthSections([
      DateTime(2025, 3),
      DateTime(2025, 2),
      DateTime(2025, 3),
    ]);

    expect(sections.map((s) => s.label), [
      'March 2025',
      'February 2025',
      'March 2025',
    ]);
    expect(sections.map((s) => s.id).toSet(), hasLength(3));
  });

  test('photos with no date share an Unknown date run', () {
    expect(runs([DateTime(2025, 3), null, null]), [
      ('March 2025', 1),
      ('Unknown date', 2),
    ]);
  });
}
