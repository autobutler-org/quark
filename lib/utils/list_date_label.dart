/// The short date a file list shows beside a file's folder (#4227): "Today",
/// "Yesterday", "Nov 11" within this year, and "Nov 11, 2024" before it.
///
/// Days are calendar days in local time, so a file saved at 23:50 reads
/// "Yesterday" ten minutes later. [now] is for tests.
String listDateLabel(DateTime time, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final local = time.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  if (day == todayDay) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  final label = '${_months[local.month - 1]} ${local.day}';
  return local.year == today.year ? label : '$label, ${local.year}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
