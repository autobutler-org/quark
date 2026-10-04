import 'package:quark/utils/fullscreen.dart';

/// A fullscreen switch that only remembers what it was told.
class FakeFullscreen implements FullscreenControl {
  FakeFullscreen({this.isSupported = true});

  @override
  final bool isSupported;

  @override
  bool isActive = false;

  @override
  Future<void> setActive(bool active) async => isActive = active;
}
