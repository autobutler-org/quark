import 'package:flutter/foundation.dart';

/// One reader's answer to a chat poll: the options they picked, the text
/// they wrote, a number, a calendar day, or a rating.
///
/// A poll with one question uses the matching field and leaves [parts]
/// empty. A poll with several questions carries one answer per question in
/// [parts], in the poll's order, and leaves the other fields empty.
@immutable
class ChatPollAnswer {
  /// Creates an answer.
  const ChatPollAnswer({
    this.choices = const [],
    this.text = '',
    this.number,
    this.date,
    this.rating,
    this.parts = const [],
  });

  /// The indices of the options picked, in ascending order.
  final List<int> choices;

  /// The free-text answer, untrimmed.
  final String text;

  /// A number question's answer, in canonical form (`3`, `3.5`), or null.
  final String? number;

  /// A date question's answer, `YYYY-MM-DD`, or null.
  final String? date;

  /// A rating question's answer, from 1 up to the question's scale, or null.
  final int? rating;

  /// One answer per question, in order, when the poll asks more than one.
  final List<ChatPollAnswer> parts;

  /// Whether this is not an answer a poll accepts: nothing picked, nothing
  /// written, and, for a poll with several questions, any question still
  /// unanswered.
  bool get isEmpty {
    if (parts.isNotEmpty) return parts.any((part) => part.isEmpty);
    return choices.isEmpty &&
        text.trim().isEmpty &&
        encodeNumber(number) == null &&
        (date == null || parseDate(date!) == null) &&
        (rating == null || rating! < 1);
  }

  /// [raw] as the number a poll stores, or null when it is not one. A whole
  /// number within the range an integer can hold exactly comes back as an
  /// `int`, so the payload says `3` rather than `3.0`.
  static num? encodeNumber(String? raw) {
    final text = numberText(raw);
    if (text == null) return null;
    return num.parse(text);
  }

  /// [value] as the canonical number text, or null when it is not a finite
  /// number. A [String] is accepted so a field can be checked as it is typed.
  static String? numberText(Object? value) {
    final n = switch (value) {
      num v when v.isFinite => v,
      String s => num.tryParse(s.trim()),
      _ => null,
    };
    if (n == null || !n.isFinite) return null;
    if (n == n.roundToDouble() && n.abs() <= _exactInt) {
      return n.toInt().toString();
    }
    return n.toString();
  }

  /// [text] as a calendar day, or null when it is not `YYYY-MM-DD` or not a
  /// real day.
  static DateTime? parseDate(String text) {
    final match = _date.firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// [date] as `YYYY-MM-DD`.
  static String formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// 2^53, the largest magnitude a whole number keeps exactly.
  static const int _exactInt = 9007199254740992;

  static final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPollAnswer &&
          listEquals(other.choices, choices) &&
          other.text == text &&
          other.number == number &&
          other.date == date &&
          other.rating == rating &&
          listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(choices),
    text,
    number,
    date,
    rating,
    Object.hashAll(parts),
  );
}
