import 'package:quark_widgets/quark_widgets.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Splits photos, given as their dates in grid order, into runs of the same
/// month and year, each headed like "March 2025" (#979).
///
/// Runs follow the order the dates arrive in and never reorder anything, so a
/// list that is not sorted by date simply gets more, shorter runs. A null date
/// joins a run headed "Unknown date". Dates are read in local time, the
/// calendar the user thinks in.
List<PhotoGridSection> photoMonthSections(Iterable<DateTime?> dates) {
  final sections = <PhotoGridSection>[];
  String? runKey;
  var count = 0;
  String label = '';

  void close() {
    if (count == 0) return;
    // The run index keeps ids unique when a month comes around twice.
    sections.add(
      PhotoGridSection(
        id: '$runKey-${sections.length}',
        label: label,
        count: count,
      ),
    );
  }

  for (final date in dates) {
    final local = date?.toLocal();
    final key = local == null ? 'unknown' : '${local.year}-${local.month}';
    if (key != runKey) {
      close();
      runKey = key;
      count = 0;
      label = local == null
          ? 'Unknown date'
          : '${_months[local.month - 1]} ${local.year}';
    }
    count++;
  }
  close();
  return sections;
}
