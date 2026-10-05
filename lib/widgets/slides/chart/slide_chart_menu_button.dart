import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_picker.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The wide tool row's chart button (#1160): opens a [SlideChartPicker]
/// that arms the chart tool or inserts a chart in the middle of the slide.
/// It is lit while the chart tool is active, and the picker starts at the
/// kind that tool draws.
///
/// Key prefixes: `slide_tool_chart` on the button; the picker's own.
class SlideChartMenuButton extends StatelessWidget {
  /// The chart button for [actions].
  const SlideChartMenuButton({required this.actions, super.key});

  /// What the picker's choices do.
  final SlideToolbarActions actions;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      SlideChartPicker(
        kind: actions.chartToolKind,
        theme: actions.controller.theme,
        onDraw: actions.drawChart,
        onInsert: actions.insertChart,
      ),
    ],
    builder: (context, menu, _) => QuarkBarIconButton(
      key: const ValueKey('slide_tool_chart'),
      icon: QuarkIcons.insert_chart,
      tooltip: 'Insert chart',
      selected: actions.chartToolActive,
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
