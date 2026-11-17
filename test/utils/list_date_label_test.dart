import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/list_date_label.dart';

/// #4227: the date a Docs, Sheets or Slides row shows beside its folder.
void main() {
  final now = DateTime(2026, 11, 16, 9, 30);

  test('today and yesterday by calendar day', () {
    expect(listDateLabel(DateTime(2026, 11, 16, 0, 5), now: now), 'Today');
    expect(
      listDateLabel(DateTime(2026, 11, 15, 23, 50), now: now),
      'Yesterday',
    );
    expect(listDateLabel(DateTime(2026, 11, 15, 0, 1), now: now), 'Yesterday');
  });

  test('a yesterday across a month boundary', () {
    expect(
      listDateLabel(DateTime(2026, 10, 31, 12), now: DateTime(2026, 11, 1, 8)),
      'Yesterday',
    );
  });

  test('older days this year read as month and day', () {
    expect(listDateLabel(DateTime(2026, 11, 11), now: now), 'Nov 11');
    expect(listDateLabel(DateTime(2026, 1, 2), now: now), 'Jan 2');
  });

  test('another year names it', () {
    expect(listDateLabel(DateTime(2024, 11, 11), now: now), 'Nov 11, 2024');
  });
}
