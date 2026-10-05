import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Two scroll controllers held at the same offset, for panes of a grid that
/// scroll together: the header strip and the body horizontally, the frozen
/// columns and the body vertically.
///
/// Scrolling either one moves the other. A move that lands during layout is
/// deferred to after the frame, since a scroll position cannot jump then.
class LinkedScrollControllers {
  /// The first pane's controller.
  final ScrollController first = ScrollController();

  /// The second pane's controller.
  final ScrollController second = ScrollController();

  bool _syncing = false;

  /// Creates the pair and links them.
  LinkedScrollControllers() {
    first.addListener(() => _follow(first, second));
    second.addListener(() => _follow(second, first));
  }

  void _follow(ScrollController leader, ScrollController follower) {
    if (_syncing || !leader.hasClients || !follower.hasClients) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance
          .addPostFrameCallback((_) => _follow(leader, follower));
      return;
    }
    final position = follower.position;
    final target = leader.offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == follower.offset) return;
    _syncing = true;
    follower.jumpTo(target);
    _syncing = false;
  }

  /// Disposes both controllers.
  void dispose() {
    first.dispose();
    second.dispose();
  }
}
