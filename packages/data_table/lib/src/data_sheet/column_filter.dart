import 'package:flutter/foundation.dart' show immutable, setEquals;

/// The comparisons a [FilterCondition] can make against a cell's value.
///
/// Text comparisons ignore case. Number comparisons need both the value and
/// the operand to parse as numbers; a value that does not fails the condition.
enum FilterConditionKind {
  /// The value contains the operand.
  contains('contains', 'Text contains'),

  /// The value does not contain the operand.
  doesNotContain('doesNotContain', 'Text does not contain'),

  /// The value equals the operand: numerically when both are numbers, as
  /// text otherwise.
  equals('equals', 'Is equal to'),

  /// The value is a number greater than the operand.
  greaterThan('greaterThan', 'Greater than'),

  /// The value is a number less than the operand.
  lessThan('lessThan', 'Less than');

  /// The name this kind is saved under.
  final String jsonName;

  /// What the filter popover calls this kind.
  final String label;

  const FilterConditionKind(this.jsonName, this.label);
}

/// One comparison a [ColumnFilter] applies to every cell in its column, such
/// as "greater than 10".
@immutable
class FilterCondition {
  /// The comparison to make.
  final FilterConditionKind kind;

  /// What the cell's value is compared with, as typed.
  final String value;

  /// A condition that compares each cell with [value] by [kind].
  const FilterCondition(this.kind, this.value);

  /// True when [cell], a displayed cell value, passes this condition.
  bool matches(String cell) {
    final text = cell.toLowerCase();
    final operand = value.toLowerCase();
    final a = num.tryParse(cell.trim());
    final b = num.tryParse(value.trim());
    return switch (kind) {
      FilterConditionKind.contains => text.contains(operand),
      FilterConditionKind.doesNotContain => !text.contains(operand),
      FilterConditionKind.equals =>
        a != null && b != null ? a == b : text.trim() == operand.trim(),
      FilterConditionKind.greaterThan => a != null && b != null && a > b,
      FilterConditionKind.lessThan => a != null && b != null && a < b,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FilterCondition && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What one column's filter lets through: every value except the
/// [hiddenValues], and, when set, only values that pass [condition].
///
/// Values are a cell's displayed text, so a formula filters by its result.
/// Blank and whitespace-only cells share the value `''`. Unchecked values
/// are stored rather than checked ones, so a value typed in after the filter
/// was set shows until someone unchecks it.
///
/// ```dart
/// controller.setColumnFilter(2, const ColumnFilter(hiddenValues: {''}));
/// ```
@immutable
class ColumnFilter {
  /// The values whose rows are hidden; `''` stands for blank cells.
  final Set<String> hiddenValues;

  /// An optional comparison every shown value must also pass.
  final FilterCondition? condition;

  /// A filter that hides [hiddenValues] and anything failing [condition].
  const ColumnFilter({this.hiddenValues = const {}, this.condition});

  /// The value a displayed cell is checked under: `''` for a blank or
  /// whitespace-only cell, the text itself otherwise.
  static String valueOf(String display) =>
      display.trim().isEmpty ? '' : display;

  /// True when this filter hides anything at all.
  bool get isActive => hiddenValues.isNotEmpty || condition != null;

  /// True when a row whose cell in this column displays [display] is shown.
  bool accepts(String display) =>
      !hiddenValues.contains(valueOf(display)) &&
      (condition?.matches(display) ?? true);

  /// This filter in the form [ColumnFilter.fromJson] reads.
  Map<String, Object> toJson() => {
        if (hiddenValues.isNotEmpty) 'hidden': [...hiddenValues],
        if (condition != null)
          'condition': {
            'kind': condition!.kind.jsonName,
            'value': condition!.value,
          },
      };

  /// The filter [toJson] saved, or null when [json] is not a map.
  ///
  /// Hidden values that are not strings and a condition of an unknown kind
  /// are dropped rather than failing the load.
  static ColumnFilter? fromJson(Object? json) {
    if (json is! Map) return null;
    final hidden = json['hidden'];
    final cond = json['condition'];
    FilterCondition? condition;
    if (cond is Map && cond['value'] is String) {
      final kind = FilterConditionKind.values
          .where((k) => k.jsonName == cond['kind'])
          .firstOrNull;
      if (kind != null) condition = FilterCondition(kind, cond['value']);
    }
    return ColumnFilter(
      hiddenValues: {
        if (hidden is List)
          for (final v in hidden)
            if (v is String) v,
      },
      condition: condition,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ColumnFilter &&
      setEquals(other.hiddenValues, hiddenValues) &&
      other.condition == condition;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(hiddenValues), condition);
}
