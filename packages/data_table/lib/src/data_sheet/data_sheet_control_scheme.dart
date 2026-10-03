import 'package:flutter/services.dart';

/// A single keyboard trigger: a logical key plus optional modifier flags.
///
/// [ctrl] matches either the Control key (Windows/Linux) or the Meta/Command
/// key (macOS), so that cross-platform defaults work without extra effort.
class KeyboardShortcut {
  final LogicalKeyboardKey key;

  /// Matches Ctrl on Windows/Linux or Cmd/Meta on macOS.
  final bool ctrl;

  final bool shift;
  final bool alt;

  const KeyboardShortcut(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
  });

  /// Creates a shortcut matching [key] held with Ctrl/Cmd.
  factory KeyboardShortcut.ctrl(LogicalKeyboardKey key) =>
      KeyboardShortcut(key, ctrl: true);

  /// Creates a shortcut matching [key] held with Ctrl/Cmd+Shift.
  factory KeyboardShortcut.ctrlShift(LogicalKeyboardKey key) =>
      KeyboardShortcut(key, ctrl: true, shift: true);

  /// Returns `true` when [event] matches this shortcut exactly.
  ///
  /// The [ctrl] flag is satisfied if either Control or Meta/Cmd is pressed,
  /// allowing the same scheme to work on both macOS and Windows/Linux.
  bool matches(KeyEvent event) {
    if (event.logicalKey != key) return false;
    final hw = HardwareKeyboard.instance;
    final ctrlOrMeta = hw.isControlPressed || hw.isMetaPressed;
    if (ctrl != ctrlOrMeta) return false;
    if (shift != hw.isShiftPressed) return false;
    if (alt != hw.isAltPressed) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'keyId': key.keyId,
        'ctrl': ctrl,
        'shift': shift,
        'alt': alt,
      };

  factory KeyboardShortcut.fromJson(Map<String, dynamic> json) =>
      KeyboardShortcut(
        LogicalKeyboardKey(json['keyId'] as int),
        ctrl: json['ctrl'] as bool? ?? false,
        shift: json['shift'] as bool? ?? false,
        alt: json['alt'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is KeyboardShortcut &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt);

  @override
  String toString() =>
      'KeyboardShortcut(${key.debugName}, ctrl: $ctrl, shift: $shift, alt: $alt)';
}

/// Maps every logical DataSheet action to one or more [KeyboardShortcut]
/// triggers.
///
/// Any trigger in an action's list will activate that action. An empty list
/// disables the action entirely, which is useful for actions that conflict with
/// an app's own key bindings.
///
/// ### Usage
///
/// ```dart
/// // Use the built-in defaults.
/// DataSheet(controller: ctrl, controlScheme: DataSheetControlScheme.defaults())
///
/// // Override a single binding.
/// final scheme = DataSheetControlScheme.defaults().copyWith(
///   undo: [KeyboardShortcut.ctrl(LogicalKeyboardKey.keyZ)],
/// );
///
/// // Disable an action.
/// final scheme = DataSheetControlScheme.defaults().copyWith(insertRow: []);
/// ```
///
/// ### Persistence
///
/// Call [toJson] to serialize and [DataSheetControlScheme.fromJson] to
/// deserialize. The scheme carries no Flutter widget state, so it can be
/// stored in `SharedPreferences`, a file, or sent over the network as JSON.
class DataSheetControlScheme {
  // --- Navigation ---
  final List<KeyboardShortcut> moveUp;
  final List<KeyboardShortcut> moveDown;
  final List<KeyboardShortcut> moveLeft;
  final List<KeyboardShortcut> moveRight;

  /// Move to the next cell (typically Tab).
  final List<KeyboardShortcut> moveNextCell;

  /// Move to the previous cell (typically Shift+Tab).
  final List<KeyboardShortcut> movePreviousCell;

  /// Jump to column 0 of the current row (Home).
  final List<KeyboardShortcut> jumpRowStart;

  /// Jump to the last column of the current row (End).
  final List<KeyboardShortcut> jumpRowEnd;

  // --- Selection ---

  /// Grow or shrink the range one row up from its far corner (Shift+Up).
  final List<KeyboardShortcut> extendUp;

  /// Grow or shrink the range one row down (Shift+Down).
  final List<KeyboardShortcut> extendDown;

  /// Grow or shrink the range one column left (Shift+Left).
  final List<KeyboardShortcut> extendLeft;

  /// Grow or shrink the range one column right (Shift+Right).
  final List<KeyboardShortcut> extendRight;

  /// Select every cell in the sheet (Ctrl+A).
  final List<KeyboardShortcut> selectAll;

  /// Jump to row 0, column 0 (Ctrl+Home).
  final List<KeyboardShortcut> jumpToFirst;

  /// Jump to the last row and column (Ctrl+End).
  final List<KeyboardShortcut> jumpToLast;

  // --- Editing ---
  final List<KeyboardShortcut> confirmEdit;
  final List<KeyboardShortcut> enterEditMode;
  final List<KeyboardShortcut> cancelEdit;
  final List<KeyboardShortcut> clearCell;
  final List<KeyboardShortcut> undo;
  final List<KeyboardShortcut> redo;

  // --- Clipboard ---
  final List<KeyboardShortcut> copy;
  final List<KeyboardShortcut> cut;
  final List<KeyboardShortcut> paste;

  // --- Data Operations ---
  final List<KeyboardShortcut> fillDown;
  final List<KeyboardShortcut> fillRight;

  // --- Structural ---

  /// Insert a row above the highlighted cell.
  final List<KeyboardShortcut> insertRow;

  /// Delete the row of the highlighted cell.
  final List<KeyboardShortcut> deleteRow;

  /// Insert a column before the highlighted cell.
  final List<KeyboardShortcut> insertColumn;

  /// Delete the column of the highlighted cell.
  final List<KeyboardShortcut> deleteColumn;

  const DataSheetControlScheme({
    required this.moveUp,
    required this.moveDown,
    required this.moveLeft,
    required this.moveRight,
    required this.moveNextCell,
    required this.movePreviousCell,
    required this.jumpRowStart,
    required this.jumpRowEnd,
    required this.jumpToFirst,
    required this.jumpToLast,
    required this.confirmEdit,
    required this.enterEditMode,
    required this.cancelEdit,
    required this.clearCell,
    required this.undo,
    required this.redo,
    required this.copy,
    required this.cut,
    required this.paste,
    required this.fillDown,
    required this.fillRight,
    required this.insertRow,
    required this.deleteRow,
    required this.insertColumn,
    required this.deleteColumn,
    this.extendUp = const [
      KeyboardShortcut(LogicalKeyboardKey.arrowUp, shift: true)
    ],
    this.extendDown = const [
      KeyboardShortcut(LogicalKeyboardKey.arrowDown, shift: true)
    ],
    this.extendLeft = const [
      KeyboardShortcut(LogicalKeyboardKey.arrowLeft, shift: true)
    ],
    this.extendRight = const [
      KeyboardShortcut(LogicalKeyboardKey.arrowRight, shift: true)
    ],
    this.selectAll = const [
      KeyboardShortcut(LogicalKeyboardKey.keyA, ctrl: true)
    ],
  });

  /// The built-in default scheme, modeled after common spreadsheet conventions.
  ///
  /// Structural operations (insert/delete row or column) use the numpad `+`/`-`
  /// keys with Ctrl or Ctrl+Shift. For keyboards without a numpad the same
  /// actions are also bound to the regular `=` and `-` keys with the same
  /// modifiers.
  factory DataSheetControlScheme.defaults() => const DataSheetControlScheme(
        // Navigation
        moveUp: [KeyboardShortcut(LogicalKeyboardKey.arrowUp)],
        moveDown: [KeyboardShortcut(LogicalKeyboardKey.arrowDown)],
        moveLeft: [KeyboardShortcut(LogicalKeyboardKey.arrowLeft)],
        moveRight: [KeyboardShortcut(LogicalKeyboardKey.arrowRight)],
        moveNextCell: [KeyboardShortcut(LogicalKeyboardKey.tab)],
        movePreviousCell: [
          KeyboardShortcut(LogicalKeyboardKey.tab, shift: true)
        ],
        jumpRowStart: [KeyboardShortcut(LogicalKeyboardKey.home)],
        jumpRowEnd: [KeyboardShortcut(LogicalKeyboardKey.end)],
        jumpToFirst: [KeyboardShortcut(LogicalKeyboardKey.home, ctrl: true)],
        jumpToLast: [KeyboardShortcut(LogicalKeyboardKey.end, ctrl: true)],
        // Selection
        extendUp: [KeyboardShortcut(LogicalKeyboardKey.arrowUp, shift: true)],
        extendDown: [
          KeyboardShortcut(LogicalKeyboardKey.arrowDown, shift: true)
        ],
        extendLeft: [
          KeyboardShortcut(LogicalKeyboardKey.arrowLeft, shift: true)
        ],
        extendRight: [
          KeyboardShortcut(LogicalKeyboardKey.arrowRight, shift: true)
        ],
        selectAll: [KeyboardShortcut(LogicalKeyboardKey.keyA, ctrl: true)],
        // Editing
        confirmEdit: [KeyboardShortcut(LogicalKeyboardKey.enter)],
        enterEditMode: [KeyboardShortcut(LogicalKeyboardKey.f2)],
        cancelEdit: [KeyboardShortcut(LogicalKeyboardKey.escape)],
        clearCell: [
          KeyboardShortcut(LogicalKeyboardKey.delete),
          KeyboardShortcut(LogicalKeyboardKey.backspace),
        ],
        undo: [KeyboardShortcut(LogicalKeyboardKey.keyZ, ctrl: true)],
        redo: [
          KeyboardShortcut(LogicalKeyboardKey.keyY, ctrl: true),
          KeyboardShortcut(LogicalKeyboardKey.keyZ, ctrl: true, shift: true),
        ],
        // Clipboard
        copy: [KeyboardShortcut(LogicalKeyboardKey.keyC, ctrl: true)],
        cut: [KeyboardShortcut(LogicalKeyboardKey.keyX, ctrl: true)],
        paste: [KeyboardShortcut(LogicalKeyboardKey.keyV, ctrl: true)],
        // Data operations
        fillDown: [KeyboardShortcut(LogicalKeyboardKey.keyD, ctrl: true)],
        fillRight: [KeyboardShortcut(LogicalKeyboardKey.keyR, ctrl: true)],
        // Structural (numpad + regular keyboard fallbacks)
        insertRow: [
          KeyboardShortcut(LogicalKeyboardKey.numpadAdd, ctrl: true),
          KeyboardShortcut(LogicalKeyboardKey.equal, ctrl: true),
        ],
        deleteRow: [
          KeyboardShortcut(LogicalKeyboardKey.numpadSubtract, ctrl: true),
          KeyboardShortcut(LogicalKeyboardKey.minus, ctrl: true),
        ],
        insertColumn: [
          KeyboardShortcut(LogicalKeyboardKey.numpadAdd,
              ctrl: true, shift: true),
          KeyboardShortcut(LogicalKeyboardKey.equal, ctrl: true, shift: true),
        ],
        deleteColumn: [
          KeyboardShortcut(
            LogicalKeyboardKey.numpadSubtract,
            ctrl: true,
            shift: true,
          ),
          KeyboardShortcut(LogicalKeyboardKey.minus, ctrl: true, shift: true),
        ],
      );

  /// Returns a copy of this scheme with the specified actions replaced.
  DataSheetControlScheme copyWith({
    List<KeyboardShortcut>? moveUp,
    List<KeyboardShortcut>? moveDown,
    List<KeyboardShortcut>? moveLeft,
    List<KeyboardShortcut>? moveRight,
    List<KeyboardShortcut>? moveNextCell,
    List<KeyboardShortcut>? movePreviousCell,
    List<KeyboardShortcut>? jumpRowStart,
    List<KeyboardShortcut>? jumpRowEnd,
    List<KeyboardShortcut>? jumpToFirst,
    List<KeyboardShortcut>? jumpToLast,
    List<KeyboardShortcut>? confirmEdit,
    List<KeyboardShortcut>? enterEditMode,
    List<KeyboardShortcut>? cancelEdit,
    List<KeyboardShortcut>? clearCell,
    List<KeyboardShortcut>? undo,
    List<KeyboardShortcut>? redo,
    List<KeyboardShortcut>? copy,
    List<KeyboardShortcut>? cut,
    List<KeyboardShortcut>? paste,
    List<KeyboardShortcut>? fillDown,
    List<KeyboardShortcut>? fillRight,
    List<KeyboardShortcut>? insertRow,
    List<KeyboardShortcut>? deleteRow,
    List<KeyboardShortcut>? insertColumn,
    List<KeyboardShortcut>? deleteColumn,
    List<KeyboardShortcut>? extendUp,
    List<KeyboardShortcut>? extendDown,
    List<KeyboardShortcut>? extendLeft,
    List<KeyboardShortcut>? extendRight,
    List<KeyboardShortcut>? selectAll,
  }) =>
      DataSheetControlScheme(
        moveUp: moveUp ?? this.moveUp,
        moveDown: moveDown ?? this.moveDown,
        moveLeft: moveLeft ?? this.moveLeft,
        moveRight: moveRight ?? this.moveRight,
        moveNextCell: moveNextCell ?? this.moveNextCell,
        movePreviousCell: movePreviousCell ?? this.movePreviousCell,
        jumpRowStart: jumpRowStart ?? this.jumpRowStart,
        jumpRowEnd: jumpRowEnd ?? this.jumpRowEnd,
        jumpToFirst: jumpToFirst ?? this.jumpToFirst,
        jumpToLast: jumpToLast ?? this.jumpToLast,
        confirmEdit: confirmEdit ?? this.confirmEdit,
        enterEditMode: enterEditMode ?? this.enterEditMode,
        cancelEdit: cancelEdit ?? this.cancelEdit,
        clearCell: clearCell ?? this.clearCell,
        undo: undo ?? this.undo,
        redo: redo ?? this.redo,
        copy: copy ?? this.copy,
        cut: cut ?? this.cut,
        paste: paste ?? this.paste,
        fillDown: fillDown ?? this.fillDown,
        fillRight: fillRight ?? this.fillRight,
        insertRow: insertRow ?? this.insertRow,
        deleteRow: deleteRow ?? this.deleteRow,
        insertColumn: insertColumn ?? this.insertColumn,
        deleteColumn: deleteColumn ?? this.deleteColumn,
        extendUp: extendUp ?? this.extendUp,
        extendDown: extendDown ?? this.extendDown,
        extendLeft: extendLeft ?? this.extendLeft,
        extendRight: extendRight ?? this.extendRight,
        selectAll: selectAll ?? this.selectAll,
      );

  Map<String, dynamic> toJson() {
    List<Map<String, dynamic>> encodeList(List<KeyboardShortcut> list) =>
        list.map((s) => s.toJson()).toList();

    return {
      'moveUp': encodeList(moveUp),
      'moveDown': encodeList(moveDown),
      'moveLeft': encodeList(moveLeft),
      'moveRight': encodeList(moveRight),
      'moveNextCell': encodeList(moveNextCell),
      'movePreviousCell': encodeList(movePreviousCell),
      'jumpRowStart': encodeList(jumpRowStart),
      'jumpRowEnd': encodeList(jumpRowEnd),
      'jumpToFirst': encodeList(jumpToFirst),
      'jumpToLast': encodeList(jumpToLast),
      'confirmEdit': encodeList(confirmEdit),
      'enterEditMode': encodeList(enterEditMode),
      'cancelEdit': encodeList(cancelEdit),
      'clearCell': encodeList(clearCell),
      'undo': encodeList(undo),
      'redo': encodeList(redo),
      'copy': encodeList(copy),
      'cut': encodeList(cut),
      'paste': encodeList(paste),
      'fillDown': encodeList(fillDown),
      'fillRight': encodeList(fillRight),
      'insertRow': encodeList(insertRow),
      'deleteRow': encodeList(deleteRow),
      'insertColumn': encodeList(insertColumn),
      'deleteColumn': encodeList(deleteColumn),
      'extendUp': encodeList(extendUp),
      'extendDown': encodeList(extendDown),
      'extendLeft': encodeList(extendLeft),
      'extendRight': encodeList(extendRight),
      'selectAll': encodeList(selectAll),
    };
  }

  factory DataSheetControlScheme.fromJson(Map<String, dynamic> json) {
    // Actions added after a scheme was saved fall back to their defaults
    // rather than being silently disabled.
    final defaults = DataSheetControlScheme.defaults().toJson();
    List<KeyboardShortcut> decodeList(String key) {
      final raw =
          json[key] as List<dynamic>? ?? defaults[key] as List<dynamic>? ?? [];
      return raw
          .map((e) => KeyboardShortcut.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return DataSheetControlScheme(
      moveUp: decodeList('moveUp'),
      moveDown: decodeList('moveDown'),
      moveLeft: decodeList('moveLeft'),
      moveRight: decodeList('moveRight'),
      moveNextCell: decodeList('moveNextCell'),
      movePreviousCell: decodeList('movePreviousCell'),
      jumpRowStart: decodeList('jumpRowStart'),
      jumpRowEnd: decodeList('jumpRowEnd'),
      jumpToFirst: decodeList('jumpToFirst'),
      jumpToLast: decodeList('jumpToLast'),
      confirmEdit: decodeList('confirmEdit'),
      enterEditMode: decodeList('enterEditMode'),
      cancelEdit: decodeList('cancelEdit'),
      clearCell: decodeList('clearCell'),
      undo: decodeList('undo'),
      redo: decodeList('redo'),
      copy: decodeList('copy'),
      cut: decodeList('cut'),
      paste: decodeList('paste'),
      fillDown: decodeList('fillDown'),
      fillRight: decodeList('fillRight'),
      insertRow: decodeList('insertRow'),
      deleteRow: decodeList('deleteRow'),
      insertColumn: decodeList('insertColumn'),
      deleteColumn: decodeList('deleteColumn'),
      extendUp: decodeList('extendUp'),
      extendDown: decodeList('extendDown'),
      extendLeft: decodeList('extendLeft'),
      extendRight: decodeList('extendRight'),
      selectAll: decodeList('selectAll'),
    );
  }
}
