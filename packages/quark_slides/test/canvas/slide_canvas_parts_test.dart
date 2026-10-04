import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_slides/src/canvas/slide_selection_handle.dart';

void main() {
  final frame = ElementFrame(x: 0, y: 0, width: 10, height: 10);

  test('defaultSlideElementLabel names each kind of element', () {
    expect(
      defaultSlideElementLabel(TextBox(
        id: 't',
        frame: frame,
        paragraphs: [TextParagraph.plain(' Hello '), TextParagraph.plain('x')],
      )),
      'Text box: Hello',
    );
    expect(
      defaultSlideElementLabel(TextBox(id: 't', frame: frame)),
      'Empty text box',
    );
    expect(
      defaultSlideElementLabel(
        ShapeElement(id: 's', frame: frame, kind: ShapeKind.roundedRectangle),
      ),
      'Rounded rectangle shape',
    );
    expect(
      defaultSlideElementLabel(
        ImageElement(id: 'i', frame: frame, source: 'a.png'),
      ),
      'Image',
    );
    expect(
      defaultSlideElementLabel(
        LineElement(id: 'l', frame: frame, endCap: LineCap.arrow),
      ),
      'Arrow',
    );
    expect(
        defaultSlideElementLabel(LineElement(id: 'l', frame: frame)), 'Line');
    expect(
      defaultSlideElementLabel(
        UnknownElement(id: 'u', frame: frame, extra: const {'type': 'chart'}),
      ),
      'Unsupported chart element',
    );
  });

  test('handle cursors turn with the element', () {
    expect(
      SlideSelectionHandle.cursorFor(SlideHandle.right, 0),
      SystemMouseCursors.resizeLeftRight,
    );
    expect(
      SlideSelectionHandle.cursorFor(SlideHandle.right, 90),
      SystemMouseCursors.resizeUpDown,
    );
    expect(
      SlideSelectionHandle.cursorFor(SlideHandle.bottomRight, 90),
      SystemMouseCursors.resizeUpRightDownLeft,
    );
    expect(
      SlideSelectionHandle.cursorFor(SlideHandle.topLeft, 0),
      SystemMouseCursors.resizeUpLeftDownRight,
    );
    expect(
      SlideSelectionHandle.cursorFor(SlideHandle.rotate, 30),
      SystemMouseCursors.grab,
    );
  });

  test('handle keys are slide_handle_<snake_case>', () {
    expect(SlideHandle.bottomRight.keyName, 'slide_handle_bottom_right');
    expect(SlideHandle.rotate.keyName, 'slide_handle_rotate');
  });

  test('fromTheme takes its colors from the color scheme', () {
    final theme = ThemeData(colorSchemeSeed: Colors.teal);
    final style = SlideCanvasStyle.fromTheme(theme);
    expect(style.selectionColor, theme.colorScheme.primary);
    expect(style.guideColor, theme.colorScheme.tertiary);
    expect(style.handleHitSize, 48);
    expect(style.copyWith(handleSize: 16).handleSize, 16);
  });
}
