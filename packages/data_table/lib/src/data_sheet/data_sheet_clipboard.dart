import 'cell_range.dart';
import 'data_sheet_controller.dart';

/// Where a `DataSheet` and `DataSheetControlBar` send copied cells and read
/// pasted ones, as tab-separated text.
///
/// The package never touches the platform clipboard: the app supplies [read]
/// and [write], so it decides how (and whether) to reach the system clipboard.
/// Without one, both widgets share [DataSheetClipboard.memory], which copies
/// and pastes inside the app only.
///
/// ```dart
/// final clipboard = DataSheetClipboard(
///   read: () async => (await Clipboard.getData('text/plain'))?.text,
///   write: (text) => Clipboard.setData(ClipboardData(text: text)),
/// );
/// DataSheet(controller: c, table: t, clipboard: clipboard);
/// ```
class DataSheetClipboard {
  /// Returns the clipboard's text, or null when it holds none.
  final Future<String?> Function() read;

  /// Replaces the clipboard's text with the given value.
  final Future<void> Function(String text) write;

  /// A clipboard backed by [read] and [write].
  const DataSheetClipboard({required this.read, required this.write});

  static String? _memoryText;

  /// An in-app clipboard shared by every sheet, used when the app passes none.
  static final DataSheetClipboard memory = DataSheetClipboard(
    read: () async => _memoryText,
    write: (text) async => _memoryText = text,
  );

  /// Writes [range], or the selected range (the edited cell when nothing is selected) when
  /// omitted, to the clipboard as
  /// TSV.
  Future<void> copySelection(
    DataSheetController controller, [
    CellRange? range,
  ]) async {
    range ??= controller.selection.contextRange;
    if (range == null) return;
    await write(controller.rangeToTsv(range));
  }

  /// Copies [range], or the selected range, then clears it as one undo step.
  Future<void> cutSelection(
    DataSheetController controller, [
    CellRange? range,
  ]) async {
    range ??= controller.selection.contextRange;
    if (range == null) return;
    await write(controller.rangeToTsv(range));
    controller.clearRange(range);
  }

  /// Pastes the clipboard's TSV into [range], or the selected range.
  Future<void> pasteIntoSelection(
    DataSheetController controller, [
    CellRange? range,
  ]) async {
    range ??= controller.selection.contextRange;
    if (range == null) return;
    final text = await read();
    if (text == null) return;
    controller.pasteTsv(text, range);
  }
}
