import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/model_viewer/quark_model_viewer/model_viewer_painter.dart';
import 'package:quark_widgets/src/model_viewer/quark_model_viewer/model_viewer_stats.dart';

import '../support/pump.dart';

/// A 2 x 3 x 4 box, as twelve triangles over eight shared corners.
QuarkModelMesh box({bool isZUp = true}) {
  final positions = Float32List.fromList([
    0, 0, 0, 2, 0, 0, 2, 3, 0, 0, 3, 0, //
    0, 0, 4, 2, 0, 4, 2, 3, 4, 0, 3, 4,
  ]);
  final indices = Uint32List.fromList([
    0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, //
    0, 1, 5, 0, 5, 4, 2, 3, 7, 2, 7, 6,
    1, 2, 6, 1, 6, 5, 0, 4, 7, 0, 7, 3,
  ]);
  return QuarkModelMesh.fromTriangles(
    positions: positions,
    indices: indices,
    isZUp: isZUp,
  );
}

/// `QuarkModelViewer` (#2988): every state, the stats strip, the buttons,
/// and that touch, mouse and keyboard all move the camera.
void main() {
  const canvas = ValueKey('model_viewer_canvas');
  const wireframeToggle = ValueKey('model_viewer_wireframe_toggle');
  const zoomIn = ValueKey('model_viewer_zoom_in');
  const zoomOut = ValueKey('model_viewer_zoom_out');
  const reset = ValueKey('model_viewer_reset');

  /// The camera the canvas is painting with.
  QuarkModelCamera camera(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(canvas),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is ModelViewerPainter,
        ),
      ),
    );
    return (paint.painter! as ModelViewerPainter).camera;
  }

  testWidgets('shows a loader while loading', (tester) async {
    await pumpAt(tester, const QuarkModelViewer(mesh: null, isLoading: true));
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(canvas), findsNothing);
  });

  testWidgets('shows the error with a Retry button', (tester) async {
    var retried = 0;
    await pumpAt(
      tester,
      QuarkModelViewer(
        mesh: null,
        error: "Couldn't load the model.",
        onRetry: () => retried++,
      ),
    );
    expect(find.text("Couldn't load the model."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('model_viewer_retry')));
    expect(retried, 1);
  });

  testWidgets('says when there is nothing to draw', (tester) async {
    await pumpAt(tester, const QuarkModelViewer(mesh: null));
    expect(find.text('Nothing to show'), findsOneWidget);
  });

  testBothViewports('draws the model with its size and counts', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkModelViewer(mesh: box(), statusLabel: 'STL · 684 B'),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(canvas), findsOneWidget);
    expect(find.text('X 2 · Y 3 · Z 4'), findsOneWidget);
    expect(find.text('Area 52'), findsOneWidget);
    expect(find.text('Volume 24'), findsOneWidget);
    expect(find.text('12 triangles'), findsOneWidget);
    expect(find.text('8 vertices'), findsOneWidget);
    expect(find.text('STL · 684 B'), findsOneWidget);
    expect(find.text(ModelViewerStats.hint), findsOneWidget);
    expect(camera(tester), QuarkModelCamera.initial);
  });

  testBothViewports('draws a wireframe, and survives 200% text', (
    tester,
    size,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = largeTextScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAt(
      tester,
      QuarkModelViewer(mesh: box(isZUp: false), wireframe: true),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testBothViewports('the buttons meet the tap target guidelines', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(24),
        child: QuarkModelViewer(mesh: box(), onWireframeChanged: (_) {}),
      ),
      size: size,
    );
    await expectTapTargetGuidelines(tester);
  });

  testWidgets('the wireframe button and the W key ask for the other mode', (
    tester,
  ) async {
    final asked = <bool>[];
    await pumpAt(
      tester,
      QuarkModelViewer(mesh: box(), onWireframeChanged: asked.add),
    );
    await tester.tap(find.byKey(wireframeToggle));
    await tester.tap(find.byKey(canvas));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(asked, [true, true]);
    // Let the double-tap the canvas tap might have started run out.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('without a handler the wireframe button is disabled', (
    tester,
  ) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()));
    final button = tester.widget<QuarkBarIconButton>(
      find.byKey(wireframeToggle),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('zoom buttons move the camera and reset brings it back', (
    tester,
  ) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()));
    await tester.tap(find.byKey(zoomIn));
    await tester.pump();
    expect(camera(tester).zoom, closeTo(QuarkModelViewer.zoomStep, 1e-9));
    await tester.tap(find.byKey(zoomOut));
    await tester.tap(find.byKey(zoomOut));
    await tester.pump();
    expect(camera(tester).zoom, closeTo(1 / QuarkModelViewer.zoomStep, 1e-9));
    await tester.tap(find.byKey(reset));
    await tester.pump();
    expect(camera(tester), QuarkModelCamera.initial);
  });

  testWidgets('one finger turns, two move, pinch zooms, double-tap resets', (
    tester,
  ) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()), size: narrowViewport);
    final center = tester.getCenter(find.byKey(canvas));

    await tester.dragFrom(center, const Offset(100, 40));
    await tester.pump();
    final turned = camera(tester);
    expect(turned.yaw, isNot(QuarkModelCamera.initial.yaw));
    expect(turned.pitch, greaterThan(QuarkModelCamera.initial.pitch));
    expect(turned.panX, 0);

    final first = await tester.startGesture(center - const Offset(40, 0));
    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    for (var step = 1; step <= 5; step++) {
      await first.moveBy(const Offset(-8, 10));
      await second.moveBy(const Offset(12, 10));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pump();
    final moved = camera(tester);
    expect(moved.yaw, turned.yaw);
    expect(moved.panY, lessThan(0));
    expect(moved.zoom, greaterThan(1));

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(camera(tester), QuarkModelCamera.initial);
  });

  testWidgets('the mouse wheel zooms and a right-drag moves', (tester) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()));
    final center = tester.getCenter(find.byKey(canvas));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await tester.pump();
    expect(camera(tester).zoom, greaterThan(1));

    final drag = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await drag.moveBy(const Offset(50, 0));
    await drag.up();
    await tester.pump();
    expect(camera(tester).panX, greaterThan(0));
    expect(camera(tester).yaw, QuarkModelCamera.initial.yaw);
  });

  /// The mesh the canvas is painting.
  QuarkModelMesh painted(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(canvas),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is ModelViewerPainter,
        ),
      ),
    );
    return (paint.painter! as ModelViewerPainter).renderer.mesh;
  }

  /// [box] carrying a one-triangle preview.
  QuarkModelMesh previewed() {
    final full = box();
    return QuarkModelMesh(
      positions: full.positions,
      indices: full.indices,
      normals: full.normals,
      min: full.min,
      max: full.max,
      isZUp: full.isZUp,
      preview: QuarkModelMesh(
        positions: Float32List.fromList([0, 0, 0, 2, 0, 0, 0, 3, 4]),
        indices: Uint32List.fromList([0, 1, 2]),
        normals: Float32List(3),
        min: full.min,
        max: full.max,
        isZUp: full.isZUp,
      ),
    );
  }

  testBothViewports('a drag draws the preview until it ends', (
    tester,
    size,
  ) async {
    final mesh = previewed();
    await pumpAt(tester, QuarkModelViewer(mesh: mesh), size: size);
    expect(painted(tester), same(mesh));

    final center = tester.getCenter(find.byKey(canvas));
    final drag = await tester.startGesture(center);
    for (var step = 0; step < 5; step++) {
      await drag.moveBy(const Offset(20, 8));
      await tester.pump();
    }
    expect(painted(tester), same(mesh.preview));
    expect(camera(tester).yaw, isNot(QuarkModelCamera.initial.yaw));
    // The counts are still the full model's.
    expect(find.text('12 triangles'), findsOneWidget);

    await drag.up();
    await tester.pump();
    expect(painted(tester), same(mesh));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('the wheel draws the preview until it rests', (tester) async {
    final mesh = previewed();
    await pumpAt(tester, QuarkModelViewer(mesh: mesh));
    final center = tester.getCenter(find.byKey(canvas));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await tester.pump();
    expect(painted(tester), same(mesh.preview));
    expect(camera(tester).zoom, greaterThan(1));

    await tester.pump(QuarkModelViewer.settleDelay);
    expect(painted(tester), same(mesh));
  });

  testWidgets('a model without a preview is always drawn in full', (
    tester,
  ) async {
    final mesh = box();
    await pumpAt(tester, QuarkModelViewer(mesh: mesh));
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(canvas)),
    );
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(painted(tester), same(mesh));
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('arrows turn, Shift+arrows move, +/- zoom, 0 resets', (
    tester,
  ) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()));
    await tester.tap(find.byKey(canvas));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      camera(tester).yaw,
      closeTo(QuarkModelCamera.initial.yaw + QuarkModelViewer.keyTurn, 1e-9),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(camera(tester).panY, closeTo(QuarkModelViewer.keyPan, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    expect(camera(tester).zoom, closeTo(QuarkModelViewer.zoomStep, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(camera(tester).zoom, closeTo(1, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pump();
    expect(camera(tester), QuarkModelCamera.initial);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a new model starts from the initial view', (tester) async {
    Widget viewer(QuarkModelMesh mesh) => QuarkModelViewer(mesh: mesh);
    await pumpAt(tester, viewer(box()));
    await tester.tap(find.byKey(zoomIn));
    await tester.pump();
    expect(camera(tester).zoom, isNot(1));
    await pumpAt(tester, viewer(box()));
    expect(camera(tester), QuarkModelCamera.initial);
  });

  testWidgets('says when the mesh is open', (tester) async {
    final full = box();
    final open = QuarkModelMesh.fromTriangles(
      positions: full.positions,
      indices: Uint32List.sublistView(full.indices, 6),
    );
    await pumpAt(tester, QuarkModelViewer(mesh: open));
    final volume = tester.widget<Text>(
      find.byKey(const ValueKey('model_viewer_volume')),
    );
    expect(volume.data, matches(RegExp(r'^Volume ≈ [\d.]+, mesh is open$')));
  });

  testWidgets('uses the measurements a mesh carries', (tester) async {
    final full = box();
    final mesh = QuarkModelMesh(
      positions: full.positions,
      indices: full.indices,
      normals: full.normals,
      min: full.min,
      max: full.max,
      measurements: const QuarkModelMeasurements(
        volume: 7,
        surfaceArea: 9,
        isClosed: true,
      ),
    );
    await pumpAt(tester, QuarkModelViewer(mesh: mesh));
    expect(find.text('Volume 7'), findsOneWidget);
    expect(find.text('Area 9'), findsOneWidget);
  });

  testWidgets('without handlers the unit and bed chips are left out', (
    tester,
  ) async {
    await pumpAt(tester, QuarkModelViewer(mesh: box()));
    expect(find.byKey(const ValueKey('model_viewer_unit')), findsNothing);
    expect(find.byKey(const ValueKey('model_viewer_bed')), findsNothing);
    expect(find.byKey(const ValueKey('model_viewer_bed_fit')), findsNothing);
  });

  testWidgets('a unit labels the sizes, area and volume', (tester) async {
    final picked = <QuarkModelUnit>[];
    await pumpAt(
      tester,
      QuarkModelViewer(
        mesh: box(),
        unit: QuarkModelUnit.millimeters,
        onUnitChanged: picked.add,
      ),
    );
    expect(find.text('X 2 · Y 3 · Z 4 mm'), findsOneWidget);
    expect(find.text('Area 52 mm²'), findsOneWidget);
    expect(find.text('Volume 24 mm³'), findsOneWidget);
    expect(find.text('Units: mm'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model_viewer_unit')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_unit_option_inches')),
    );
    await tester.pumpAndSettle();
    expect(picked, [QuarkModelUnit.inches]);
  });

  testWidgets('the bed chip picks a bed and the strip says if it fits', (
    tester,
  ) async {
    QuarkPrintBed? picked = QuarkPrintBed.common.first;
    await pumpAt(
      tester,
      QuarkModelViewer(mesh: box(), onPrintBedChanged: (bed) => picked = bed),
    );
    expect(find.text('Bed: none'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('model_viewer_bed')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_bed_option_ender_3')),
    );
    await tester.pumpAndSettle();
    expect(picked?.id, 'ender_3');

    await tester.tap(find.byKey(const ValueKey('model_viewer_bed')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_viewer_bed_option_none')),
    );
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('the fit is checked in the unit picked', (tester) async {
    const bed = QuarkPrintBed(
      id: 'tiny',
      name: 'Tiny',
      width: 60,
      depth: 60,
      height: 60,
    );
    Widget viewer(QuarkModelUnit unit) => QuarkModelViewer(
      mesh: box(),
      unit: unit,
      printBed: bed,
      onPrintBedChanged: (_) {},
    );
    await pumpAt(tester, viewer(QuarkModelUnit.file));
    expect(find.text('Fits Tiny if in mm'), findsOneWidget);
    await pumpAt(tester, viewer(QuarkModelUnit.millimeters));
    expect(find.text('Fits Tiny'), findsOneWidget);
    // Four inches is 101.6 mm, taller than the bed.
    await pumpAt(tester, viewer(QuarkModelUnit.inches));
    expect(find.text('Too big for Tiny'), findsOneWidget);
  });

  testBothViewports('the chips and the fit survive 200% text', (
    tester,
    size,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = largeTextScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAt(
      tester,
      QuarkModelViewer(
        mesh: box(),
        unit: QuarkModelUnit.inches,
        onUnitChanged: (_) {},
        printBed: QuarkPrintBed.common.last,
        onPrintBedChanged: (_) {},
        statusLabel: 'STL · 684 B',
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  test('the camera clamps its pitch and zoom', () {
    final camera = QuarkModelCamera.initial.orbit(0, 10).zoomBy(1000);
    expect(camera.pitch, QuarkModelCamera.maxPitch);
    expect(camera.zoom, QuarkModelCamera.maxZoom);
    expect(
      QuarkModelCamera.initial.zoomBy(0.0001).zoom,
      QuarkModelCamera.minZoom,
    );
  });

  test('lengths keep three significant decimals at most', () {
    expect(formatModelLength(120), '120');
    expect(formatModelLength(45.25), '45.25');
    expect(formatModelLength(1234.56), '1234.6');
    expect(formatModelLength(0.125), '0.125');
    expect(formatModelLength(-0.0001), '0');
  });
}
