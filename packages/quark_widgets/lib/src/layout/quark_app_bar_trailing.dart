import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// App-wide controls every main page's bar shows after its own actions, such
/// as a running-jobs badge.
///
/// The package cannot read app state, so the app provides this once, above
/// its pages, and `QuarkAppBar` reads it. Without a scope the bars render
/// only their own actions, which is what the gallery and tests see.
///
/// Emits no `ValueKey`s of its own; each widget in [actions] carries its own.
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => QuarkAppBarTrailing(
///     actions: [JobsBadge(runningCount: count, onTap: openJobs)],
///     child: child!,
///   ),
/// );
/// ```
class QuarkAppBarTrailing extends InheritedWidget {
  /// Provides [actions] to every bar below.
  const QuarkAppBarTrailing({
    required this.actions,
    required super.child,
    super.key,
  });

  /// The controls appended to every bar that reads this scope, in order.
  final List<Widget> actions;

  /// The nearest scope's [actions], or none when there is no scope.
  static List<Widget> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QuarkAppBarTrailing>()
          ?.actions ??
      const [];

  @override
  bool updateShouldNotify(QuarkAppBarTrailing oldWidget) =>
      !listEquals(oldWidget.actions, actions);
}
