import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The rule across a message list where one day's messages end and the next
/// day's begin, with the date in the middle.
///
/// A part of `QuarkMessageList`, tested through it.
class ChatDaySeparator extends StatelessWidget {
  /// Creates the separator for the day [date] falls on.
  const ChatDaySeparator({required this.date, super.key});

  /// Any moment on the day to label. Only the date is used.
  final DateTime date;

  static const List<String> _months = [
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

  /// The label drawn for [date], such as `September 24, 2026`.
  static String labelFor(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
      child: Row(
        children: [
          Expanded(child: Divider(color: tokens.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Text(
              labelFor(date),
              style: TextStyle(
                color: tokens.mutedForeground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: tokens.border)),
        ],
      ),
    );
  }
}
