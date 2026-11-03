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
/// oldest first. The first column is who answered, named through [nameOf],
/// and is left out of an anonymous poll altogether; then one column per
/// question, a choice as its option's label and text as written.
///
/// Call it only for an entry with a [ChatTimelineMessage.question].
List<List<String>> chatPollExportRows(
  ChatTimelineMessage entry,
  String Function(int userId) nameOf,
) {
  final question = entry.question!;
  final named = !entry.message.poll!.anonymous;
  return [
    [if (named) 'Name', question.prompt],
    for (final ChatOpenPollAnswer(:response, :answer) in entry.pollAnswers)
      if (answer != null)
        [
          if (named) nameOf(response.userId ?? 0),
          question.type == ChatPollType.text
              ? answer.text
              : answer.choices.map((c) => question.options[c]).join('; '),
        ],
  ];
}

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
