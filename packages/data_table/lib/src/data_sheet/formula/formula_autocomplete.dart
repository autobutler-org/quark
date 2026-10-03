import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_formula/evaluation/evaluation.dart'
    show BuiltinFunction, builtinsMatching;

import 'formula_editing.dart';
import 'formula_suggestion_list.dart';

/// Function autocomplete for a formula text field: wraps the field ([child]) and, while it has focus and the
/// caret ends a function name being typed ([functionQueryAt]), shows the matching built-ins in a
/// [FormulaSuggestionList] popover below it, or above it when there is more room there.
///
/// While the list is open, Up and Down move the highlight, Tab or Enter accepts it ([acceptFunction] writes the
/// name and its `(`), and Escape closes the list until the text changes. Tapping a row accepts it. Every other key,
/// and these keys while the list is closed, reach the field and its ancestors as usual.
///
/// ```dart
/// FormulaAutocomplete(controller: controller, child: TextField(controller: controller))
/// ```
class FormulaAutocomplete extends StatefulWidget {
  /// The field's controller, read for the name being typed and written when a function is accepted.
  final TextEditingController controller;

  /// The text field.
  final Widget child;

  const FormulaAutocomplete({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<FormulaAutocomplete> createState() => _FormulaAutocompleteState();
}

class _FormulaAutocompleteState extends State<FormulaAutocomplete> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _selectedKey = GlobalKey();

  bool _focused = false;
  FunctionQuery? _query;
  List<BuiltinFunction> _matches = const [];
  int _index = 0;

  /// The text Escape closed the list on; it stays closed until the text changes.
  String? _dismissedText;

  bool get _open => _matches.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(FormulaAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _update();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final value = widget.controller.value;
    if (_dismissedText != null && _dismissedText != value.text) {
      _dismissedText = null;
    }
    final query =
        _focused && _dismissedText == null ? functionQueryAt(value) : null;
    final matches = query == null
        ? const <BuiltinFunction>[]
        : builtinsMatching(query.prefix);
    final sameList = matches.length == _matches.length &&
        Iterable.generate(matches.length)
            .every((i) => matches[i].name == _matches[i].name);
    setState(() {
      _query = query;
      if (!sameList) _index = 0;
      _matches = matches;
    });
    if (_open) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  void _accept(BuiltinFunction function) {
    final query = _query;
    if (query == null) return;
    widget.controller.value =
        acceptFunction(widget.controller.value, query, function.name);
  }

  void _move(int step) {
    setState(() {
      _index = (_index + step) % _matches.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: step > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_open || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (event is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _accept(_matches[_index]);
    } else if (key == LogicalKeyboardKey.escape) {
      _dismissedText = widget.controller.text;
      _update();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        _focused = focused;
        _update();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: KeyedSubtree(key: _fieldKey, child: widget.child),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final field = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (field == null || !field.hasSize || overlay == null || !_open) {
      return const SizedBox.shrink();
    }
    final topLeft = field.localToGlobal(Offset.zero, ancestor: overlay);
    return CustomSingleChildLayout(
      delegate: _BelowOrAboveLayout(topLeft & field.size),
      child: TextFieldTapRegion(
        child: FormulaSuggestionList(
          functions: _matches,
          selectedIndex: _index,
          selectedKey: _selectedKey,
          onSelected: _accept,
        ),
      ),
    );
  }
}

/// Places the list under [anchor], or over it when more room is there, kept inside the overlay with an 8-pixel
/// margin and at most 320 wide and 280 tall.
class _BelowOrAboveLayout extends SingleChildLayoutDelegate {
  final Rect anchor;

  const _BelowOrAboveLayout(this.anchor);

  static const double _margin = 8;

  double _below(Size size) => size.height - anchor.bottom - _margin;

  double _above() => anchor.top - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final room = math.max(_below(size), _above());
    return BoxConstraints(
      maxWidth: math.max(0, math.min(320, size.width - 2 * _margin)),
      maxHeight: math.max(0, math.min(280, room)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = math.min(
      math.max(anchor.left, _margin),
      math.max(_margin, size.width - childSize.width - _margin),
    );
    final fitsBelow =
        childSize.height <= _below(size) || _below(size) >= _above();
    final y = fitsBelow ? anchor.bottom : anchor.top - childSize.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BelowOrAboveLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}
