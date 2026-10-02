import 'package:open_file/open_file.dart';

/// Opens the file at [path] in whichever app the system picks for it. Returns an error message when no app could open
/// it, or an empty string on success.
Future<String> openFileWithSystem(String path) async {
  final result = await OpenFile.open(path);
  if (result.type != ResultType.done) {
    return result.message;
  }
  return '';
}
