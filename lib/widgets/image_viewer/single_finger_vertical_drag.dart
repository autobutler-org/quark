import 'package:flutter/gestures.dart';

/// A vertical drag that gives up the moment a second finger lands.
///
/// The photo viewer closes on a swipe down, and its photo zooms on a pinch.
/// A pinch whose lower finger does the moving crosses the drag's slop before
/// the zoom's, so a plain [VerticalDragGestureRecognizer] would win it and
/// close the viewer mid-pinch (#3358). Rejecting as soon as two pointers are
/// down leaves the pinch to the zoom.
class SingleFingerVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  /// Creates the recognizer for the [supportedDevices] given.
  SingleFingerVerticalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
  });

  final Set<int> _pointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointers.add(event.pointer);
    if (_pointers.length > 1) resolve(GestureDisposition.rejected);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}
