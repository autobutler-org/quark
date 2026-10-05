import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../controller/slide_document_controller.dart';
import '../geometry/slide_tree.dart';
import '../model/chart_data.dart';
import '../model/chart_kind.dart';
import '../model/slide_color.dart';
import '../model/slide_element.dart';

/// The chart selected on an editing `SlideCanvas`, and the chart commands a
/// toolbar sends to it: the toolbar API for charts.
///
/// Give one to `SlideCanvas.chartEditing` and to the toolbar, and keep it
/// for the canvas's life (the canvas makes its own when none is given). The
/// canvas tells it what is selected as it builds; when exactly one chart
/// is, [chart] is that chart and the commands — each **one undo step** on
/// the document — change it. It notifies after each command and when the
/// selected chart changes, so a toolbar can show its chart controls only
/// while [hasChart]:
///
/// ```dart
/// final charts = SlideChartEditingController();
/// SlideCanvas(document: doc, slideId: slideId, chartEditing: charts, ...);
///
/// ListenableBuilder(
///   listenable: charts,
///   builder: (context, _) => !charts.hasChart
///       ? const SizedBox.shrink()
///       : Row(children: [
///           DropdownButton<ChartKind>(
///             value: charts.chart!.kind,
///             items: [
///               for (final kind in ChartKind.values)
///                 DropdownMenuItem(value: kind, child: Text(chartKindName(kind))),
///             ],
///             onChanged: charts.canEdit ? (k) => charts.setKind(k!) : null,
///           ),
///           Switch(
///             value: charts.chart!.options.showLegend,
///             onChanged: charts.canEdit
///                 ? (on) => charts.setOptions(showLegend: on)
///                 : null,
///           ),
///         ]),
/// );
///
/// // A data sheet edits the numbers as a grid of text:
/// final grid = charts.grid; // [['', 'Revenue'], ['Q1', '12'], ...]
/// charts.setDataGrid(editedGrid);
/// ```
///
/// On a canvas that does not edit (`SlideCanvasInteraction.selectOnly`)
/// [chart] still reports the selected chart, so its data can be shown, but
/// [canEdit] is false and every command does nothing.
class SlideChartEditingController extends ChangeNotifier {
  SlideDocumentController? _doc;
  String? _slideId;
  String? _chartId;
  bool _editable = true;
  bool _disposed = false;

  /// Points the controller at the slide [slideId] of [document], with
  /// [selection] selected, edited only when [editable]. `SlideCanvas`
  /// calls this as it builds; an app does not need to. A change of chart
  /// notifies after the frame, never during the build.
  void attach(
    SlideDocumentController document,
    String slideId,
    Set<String> selection, {
    bool editable = true,
  }) {
    _doc = document;
    _slideId = slideId;
    final single = selection.length == 1 ? selection.single : null;
    final element = single == null
        ? null
        : document.presentation.slideById(slideId)?.findElement(single);
    final id = element is ChartElement ? element.id : null;
    if (id == _chartId && editable == _editable) return;
    _chartId = id;
    _editable = editable;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  /// The selected chart as the document has it now, or `null` when no
  /// single chart is selected.
  ChartElement? get chart {
    final id = _chartId;
    final element = id == null
        ? null
        : _doc?.presentation.slideById(_slideId ?? '')?.findElement(id);
    return element is ChartElement ? element : null;
  }

  /// Whether a single chart is selected.
  bool get hasChart => chart != null;

  /// Whether the commands would change the selected chart: one is
  /// selected and the canvas edits.
  bool get canEdit => _editable && hasChart;

  /// Whether [removeSeries] may remove a series: the chart has more than
  /// one.
  bool get canRemoveSeries => canEdit && chart!.data.series.length > 1;

  /// The selected chart's data as a grid of text, series across and
  /// categories down (see `ChartData.toGrid`), or `null`.
  List<List<String>>? get grid => chart?.data.toGrid();

  /// Makes the chart a [kind] chart.
  void setKind(ChartKind kind) =>
      _onChart((doc, slide, id) => doc.setChartKind(slide, id, kind));

  /// Replaces the chart's data. Throws an [ArgumentError] past the
  /// `ChartData` limits.
  void setData(ChartData data) =>
      _onChart((doc, slide, id) => doc.setChartData(slide, id, data));

  /// Replaces the chart's data with what a data sheet's [grid] holds (see
  /// `ChartData.fromGrid`).
  void setDataGrid(List<List<String>> grid) =>
      setData(ChartData.fromGrid(grid));

  /// Sets the chart's title, legend, value labels, gridlines and axis
  /// titles; what is left out is kept.
  void setOptions({
    String? title,
    bool? showLegend,
    bool? showDataLabels,
    bool? showGridlines,
    String? categoryAxisTitle,
    String? valueAxisTitle,
  }) =>
      _onChart(
        (doc, slide, id) => doc.setChartOptions(
          slide,
          id,
          title: title,
          showLegend: showLegend,
          showDataLabels: showDataLabels,
          showGridlines: showGridlines,
          categoryAxisTitle: categoryAxisTitle,
          valueAxisTitle: valueAxisTitle,
        ),
      );

  /// Adds a series after the last: [name] ("Series N" by default) with
  /// [values] (zeros by default).
  void addSeries({String? name, List<double>? values}) => _onChart(
        (doc, slide, id) =>
            doc.addChartSeries(slide, id, name: name, values: values),
      );

  /// Removes series [index], unless it is the only one.
  void removeSeries(int index) {
    if (!canRemoveSeries) return;
    _onChart((doc, slide, id) => doc.removeChartSeries(slide, id, index));
  }

  /// Sets the colors of the series — a pie's slices — in order; see
  /// `SlideDocumentController.setChartColors`.
  void setColors(List<SlideColor> colors) =>
      _onChart((doc, slide, id) => doc.setChartColors(slide, id, colors));

  /// Runs [command] on the selected chart, when it may, and notifies.
  void _onChart(
    void Function(SlideDocumentController doc, String slideId, String chartId)
        command,
  ) {
    final doc = _doc;
    if (doc == null || !canEdit) return;
    command(doc, _slideId!, _chartId!);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
