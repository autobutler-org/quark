import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Mixin that provides [setStateSafely], a drop-in replacement for [setState]
/// that guards against calling setState during an active build phase or after
/// the widget has been unmounted.
mixin SafeSetStateMixin<T extends StatefulWidget> on State<T> {
  void setStateSafely(VoidCallback update) {
    if (!mounted) {
      return;
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(update);
      });
      return;
    }

    setState(update);
  }
}

/// The [ChangeNotifier] twin of [SafeSetStateMixin]: [notifyListeners] after
/// [dispose] does nothing instead of throwing, so an answer that lands after
/// the page closed is dropped. [isDisposed] tells an async step to stop.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
