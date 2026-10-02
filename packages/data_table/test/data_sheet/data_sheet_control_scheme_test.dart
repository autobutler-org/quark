import 'package:data_table/src/data_sheet/data_sheet_control_scheme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataSheetControlScheme selection bindings', () {
    test('defaults bind Shift+arrows and Ctrl+A', () {
      final scheme = DataSheetControlScheme.defaults();
      expect(scheme.extendDown, [
        const KeyboardShortcut(LogicalKeyboardKey.arrowDown, shift: true),
      ]);
      expect(scheme.extendLeft.single.shift, true);
      expect(scheme.selectAll, [
        KeyboardShortcut.ctrl(LogicalKeyboardKey.keyA),
      ]);
    });

    test('round-trips through JSON', () {
      final scheme = DataSheetControlScheme.defaults().copyWith(
        extendUp: [KeyboardShortcut.ctrlShift(LogicalKeyboardKey.keyK)],
        selectAll: [],
      );
      final restored = DataSheetControlScheme.fromJson(scheme.toJson());
      expect(restored.extendUp, scheme.extendUp);
      expect(restored.selectAll, isEmpty);
    });

    test('a scheme saved before selection existed gets the defaults', () {
      final json = DataSheetControlScheme.defaults().toJson()
        ..remove('extendRight')
        ..remove('selectAll');
      final restored = DataSheetControlScheme.fromJson(json);
      expect(
        restored.extendRight,
        DataSheetControlScheme.defaults().extendRight,
      );
      expect(restored.selectAll, DataSheetControlScheme.defaults().selectAll);
    });
  });
}
