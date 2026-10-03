import 'package:flutter/material.dart' hide Icons;
import 'package:quark_icons/quark_icons.dart';

import '../column_filter.dart';

/// The body of a column's filter popover: a condition, a searchable checklist
/// of the column's values with "Select all", and Clear, Cancel and Apply.
///
/// Nothing changes until Apply, which hands [onApply] the edited filter. Clear
/// hands it an empty filter, which removes the column's filter. "Select all"
/// checks or unchecks only the values the search matches, so search, then
/// Select all, picks out just those values. Blank cells are listed last as
/// "(Blanks)".
///
/// Keys: `column_filter_condition`, `column_filter_condition_value`,
/// `column_filter_search`, `column_filter_select_all`,
/// `column_filter_value_<value>` (`column_filter_blanks` for blanks),
/// `column_filter_clear`, `column_filter_cancel` and `column_filter_apply`.
///
/// ```dart
/// ColumnFilterPanel(
///   columnLabel: 'B',
///   values: controller.filterValuesFor(1),
///   initial: controller.filterFor(1),
///   onApply: (f) => controller.setColumnFilter(1, f),
///   onCancel: close,
/// )
/// ```
class ColumnFilterPanel extends StatefulWidget {
  /// The column's letter, such as `B`, for the title.
  final String columnLabel;

  /// The values to list, in order; `''` stands for blank cells.
  final List<String> values;

  /// The column's current filter, or null when it has none.
  final ColumnFilter? initial;

  /// Called with the filter to set when Apply or Clear is pressed.
  final ValueChanged<ColumnFilter> onApply;

  /// Called when Cancel is pressed.
  final VoidCallback onCancel;

  /// A filter editor for one column, starting from [initial].
  const ColumnFilterPanel({
    super.key,
    required this.columnLabel,
    required this.values,
    required this.onApply,
    required this.onCancel,
    this.initial,
  });

  @override
  State<ColumnFilterPanel> createState() => _ColumnFilterPanelState();
}

class _ColumnFilterPanelState extends State<ColumnFilterPanel> {
  /// The tallest the value list grows before it scrolls.
  static const double _maxListHeight = 240;

  late final Set<String> _hidden = {...?widget.initial?.hiddenValues};
  late FilterConditionKind? _kind = widget.initial?.condition?.kind;
  late final TextEditingController _operand =
      TextEditingController(text: widget.initial?.condition?.value ?? '');
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _operand.dispose();
    _search.dispose();
    super.dispose();
  }

  List<String> get _matching {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.values;
    return [
      for (final v in widget.values)
        if (_label(v).toLowerCase().contains(q)) v,
    ];
  }

  static String _label(String value) => value.isEmpty ? '(Blanks)' : value;

  void _apply() {
    final operand = _operand.text;
    widget.onApply(ColumnFilter(
      hiddenValues: _hidden.intersection(widget.values.toSet()),
      condition: _kind != null && operand.trim().isNotEmpty
          ? FilterCondition(_kind!, operand)
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matching = _matching;
    final shown = matching.where((v) => !_hidden.contains(v)).length;
    final selectAll = shown == matching.length
        ? true
        : shown == 0
            ? false
            : null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Filter column ${widget.columnLabel}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButton<FilterConditionKind?>(
                  key: const ValueKey('column_filter_condition'),
                  isExpanded: true,
                  isDense: true,
                  value: _kind,
                  onChanged: (k) => setState(() => _kind = k),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No condition'),
                    ),
                    for (final k in FilterConditionKind.values)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                  ],
                ),
              ),
              if (_kind != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: const ValueKey('column_filter_condition_value'),
                    controller: _operand,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Value',
                    ),
                    onSubmitted: (_) => _apply(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('column_filter_search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(QuarkIcons.search, size: 18),
              hintText: 'Search values',
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('column_filter_select_all'),
            dense: true,
            tristate: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Select all'),
            value: selectAll,
            onChanged: matching.isEmpty
                ? null
                : (_) => setState(() {
                      if (selectAll == true) {
                        _hidden.addAll(matching);
                      } else {
                        _hidden.removeAll(matching);
                      }
                    }),
          ),
          const Divider(height: 1),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: matching.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No matching values',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matching.length,
                      itemBuilder: (context, i) {
                        final v = matching[i];
                        return CheckboxListTile(
                          key: ValueKey(
                            v.isEmpty
                                ? 'column_filter_blanks'
                                : 'column_filter_value_$v',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            _label(v),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: !_hidden.contains(v),
                          onChanged: (show) => setState(() {
                            if (show ?? false) {
                              _hidden.remove(v);
                            } else {
                              _hidden.add(v);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 4,
            children: [
              TextButton(
                key: const ValueKey('column_filter_clear'),
                onPressed: () => widget.onApply(const ColumnFilter()),
                child: const Text('Clear'),
              ),
              TextButton(
                key: const ValueKey('column_filter_cancel'),
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('column_filter_apply'),
                onPressed: _apply,
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
