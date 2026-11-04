import 'dart:convert';

import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/utils/csv_writer.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The formats a poll's results export as (#3894).
enum ChatPollExportFormat {
  /// A header row, then one row per respondent.
  csv('CSV'),

  /// One object per respondent, keyed by the header row.
  json('JSON'),

  /// A Quark spreadsheet with the CSV's rows on one `Results` tab.
  qsheet('Sheet');

  const ChatPollExportFormat(this.label);

  /// What the format is called where it is picked.
  final String label;

  /// What the saved file is called: the poll's [prompt] with the characters
  /// a file system rejects dropped, capped at 80 characters, or
  /// `poll_results` when nothing usable is left.
  String fileNameFor(String prompt) {
    final cleaned = prompt
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final capped = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
    final stem = capped.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
    return '${stem.isEmpty ? 'poll_results' : stem}.$name';
  }
}

/// Where a poll export goes, picked when it is made.
enum ChatPollExportDestination {
  /// This device: the browser's download, or the platform's save dialog.
  download,

  /// The account's home folder on the Quark, in the clear.
  quark,
}

/// [entry]'s results as rows: a header, then one row per answer that opened,
/// in the order the poll lists them. The first column is who answered, named
/// through [nameOf], and is left out of an anonymous poll altogether; then one
/// column per question. A choice is its option's label, text is written as
/// given, a number and a rating are the number, and a date is `YYYY-MM-DD`.
/// Two questions with the same wording get ` (2)`, ` (3)` and so on, so a
/// JSON export's keys stay unique.
///
/// Call it only for an entry with a [ChatTimelineMessage.question].
List<List<String>> chatPollExportRows(
  ChatTimelineMessage entry,
  String Function(int userId) nameOf,
) {
  final questions = entry.question!.questions;
  final named = !entry.message.poll!.anonymous;
  final headers = _headers(questions);
  return [
    [if (named) 'Name', ...headers],
    for (final ChatOpenPollAnswer(:response, :answer) in entry.pollAnswers)
      if (answer != null)
        [if (named) nameOf(response.userId ?? 0), ..._cells(questions, answer)],
  ];
}

List<String> _headers(List<ChatPollQuestion> questions) {
  final seen = <String, int>{};
  final headers = <String>[];
  for (final question in questions) {
    final count = (seen[question.prompt] ?? 0) + 1;
    seen[question.prompt] = count;
    headers.add(count == 1 ? question.prompt : '${question.prompt} ($count)');
  }
  return headers;
}

List<String> _cells(List<ChatPollQuestion> questions, ChatPollAnswer answer) {
  final parts = questions.length == 1 ? [answer] : answer.parts;
  return [
    for (final (index, question) in questions.indexed)
      index < parts.length ? _cell(question, parts[index]) : '',
  ];
}

String _cell(ChatPollQuestion question, ChatPollAnswer answer) =>
    switch (question.type) {
      ChatPollType.text => answer.text,
      ChatPollType.number => answer.number ?? '',
      ChatPollType.date => answer.date ?? '',
      ChatPollType.rating => answer.rating == null ? '' : '${answer.rating}',
      ChatPollType.single || ChatPollType.multiple =>
        answer.choices.map((choice) => question.options[choice]).join('; '),
    };

/// [rows] from [chatPollExportRows] as the text of a [format] file. A
/// snapshot: nothing tracks the file once it is written.
String chatPollExport(List<List<String>> rows, ChatPollExportFormat format) =>
    switch (format) {
      ChatPollExportFormat.csv => csvFromRows(rows),
      ChatPollExportFormat.json => const JsonEncoder.withIndent('  ').convert([
        for (final row in rows.skip(1))
          {for (var i = 0; i < row.length; i++) rows.first[i]: row[i]},
      ]),
      ChatPollExportFormat.qsheet => jsonEncode({
        'tabs': [
          {
            'name': 'Results',
            'data': {'rows': rows},
          },
        ],
      }),
    };
