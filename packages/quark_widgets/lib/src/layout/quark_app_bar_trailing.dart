import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// App-wide controls every main page's bar shows after its own actions, such
/// as a running-jobs badge.
///
/// The package cannot read app state, so the app provides this once, above
/// its pages, and `QuarkAppBar` reads it. Without a scope the bars render
/// only their own actions, which is what the gallery and tests see.
///
/// A compact bar, on a phone, has no room for every control, so it shows
/// [compact] alone in their place (#4150): one button that opens them all,
/// such as an account button and its sheet.
///
/// Emits no `ValueKey`s of its own; each widget in [actions] and [compact]
/// carries its own.
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) => QuarkAppBarTrailing(
///     actions: [JobsBadge(runningCount: count, onTap: openJobs)],
///     compact: QuarkAccountButton(showDot: count > 0, onPressed: openSheet),
///     child: child!,
///   ),
/// );
/// ```
class QuarkAppBarTrailing extends InheritedWidget {
  /// Provides [actions] to every bar below.
  const QuarkAppBarTrailing({
    required this.actions,
    this.compact,
    required super.child,
    super.key,
  });

  /// The controls appended to every bar that reads this scope, in order.
  final List<Widget> actions;

  /// The one control a compact bar shows in place of [actions]. Null shows
  /// none.
  final Widget? compact;

  /// The nearest scope's [actions], or none when there is no scope.
  static List<Widget> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QuarkAppBarTrailing>()
          ?.actions ??
      const [];

  /// The nearest scope's [compact] control, or null when there is none.
  static Widget? compactOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<QuarkAppBarTrailing>()
      ?.compact;

  @override
  bool updateShouldNotify(QuarkAppBarTrailing oldWidget) =>
      !listEquals(oldWidget.actions, actions) || oldWidget.compact != compact;
}
