import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark/widgets/slides/find/slide_find_field.dart';
import 'package:quark/widgets/slides/find/slide_find_options.dart';
import 'package:quark/widgets/slides/find/slide_find_replace_row.dart';
import 'package:quark/widgets/slides/find/slide_find_status.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's find and replace bar (#1176), over a
/// [SlideFindController]: the query with its counter ("3 of 12"),
/// previous and next — wrapping at either end — the options, and, opened
/// with Ctrl or Cmd H or its replace button, the replace row.
///
/// Enter steps to the next match and Shift+Enter (or Shift+F3) to the
/// previous; F3 steps on too. Escape closes the bar.
///
/// Narrower than [compactBreakpoint] — a phone, where the page puts it
/// along the bottom so it sits just above the keyboard — it is a compact
/// bar: the counter moves under the query, and the option chips hide behind
/// an options button. Every control is labeled for a screen reader, takes a
/// 48 pixel target, and wraps rather than overflows at large text sizes.
/// Given less height than it needs, it scrolls. It builds nothing while
/// the controller is closed.
///
/// Key prefixes: `slide_find_bar` on the bar, `slide_find_query` on the
/// query field, `slide_find_previous`, `slide_find_next`,
/// `slide_find_toggle_replace`, `slide_find_toggle_options` and
/// `slide_find_close` on its buttons, and those of [SlideFindStatus],
/// [SlideFindOptions] and [SlideFindReplaceRow].
///
/// ```dart
/// SlideFindBar(controller: find);
/// ```
class SlideFindBar extends StatelessWidget {
  /// Creates the bar over [controller].
  const SlideFindBar({required this.controller, super.key});

  /// The find bar's state.
  final SlideFindController controller;

  /// The width below which the bar is compact.
  static const double compactBreakpoint = 600;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.isOpen) return const SizedBox.shrink();
      final tokens = QuarkTokens.of(context);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): controller.close,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true):
              controller.previous,
          const SingleActivator(LogicalKeyboardKey.f3): controller.next,
          const SingleActivator(LogicalKeyboardKey.f3, shift: true):
              controller.previous,
        },
        child: Container(
          key: const ValueKey('slide_find_bar'),
          decoration: BoxDecoration(
            color: tokens.card,
            border: Border(
              top: BorderSide(color: tokens.border),
              bottom: BorderSide(color: tokens.border),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacingSm,
            vertical: tokens.spacingXs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < compactBreakpoint;
              final status = SlideFindStatus(status: controller.status);
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: tokens.spacingXs,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SlideFindField(
                            key: const ValueKey('slide_find_query'),
                            controller: controller.query,
                            focusNode: controller.queryFocus,
                            label: 'Find',
                            icon: QuarkIcons.search_rounded,
                            onSubmitted: controller.next,
                          ),
                        ),
                        if (!compact)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: tokens.spacingSm,
                            ),
                            child: status,
                          ),
                        QuarkBarIconButton(
                          key: const ValueKey('slide_find_previous'),
                          icon: QuarkIcons.arrow_upward_rounded,
                          tooltip: 'Previous match',
                          onPressed: controller.canStep
                              ? controller.previous
                              : null,
                        ),
                        QuarkBarIconButton(
                          key: const ValueKey('slide_find_next'),
                          icon: QuarkIcons.arrow_downward_rounded,
                          tooltip: 'Next match',
                          onPressed: controller.canStep
                              ? controller.next
                              : null,
                        ),
                        if (!compact)
                          QuarkBarIconButton(
                            key: const ValueKey('slide_find_toggle_replace'),
                            icon: QuarkIcons.find_replace,
                            tooltip: 'Replace',
                            selected: controller.showReplace,
                            onPressed: controller.toggleReplace,
                          ),
                        QuarkBarIconButton(
                          key: const ValueKey('slide_find_close'),
                          icon: QuarkIcons.close_rounded,
                          tooltip: 'Close find',
                          onPressed: controller.close,
                        ),
                      ],
                    ),
                    if (compact)
                      Row(
                        children: [
                          Expanded(child: status),
                          QuarkBarIconButton(
                            key: const ValueKey('slide_find_toggle_replace'),
                            icon: QuarkIcons.find_replace,
                            tooltip: 'Replace',
                            selected: controller.showReplace,
                            onPressed: controller.toggleReplace,
                          ),
                          QuarkBarIconButton(
                            key: const ValueKey('slide_find_toggle_options'),
                            icon: QuarkIcons.tune_rounded,
                            tooltip: 'Find options',
                            selected: controller.showOptions,
                            onPressed: controller.toggleOptions,
                          ),
                        ],
                      ),
                    if (!compact || controller.showOptions)
                      SlideFindOptions(controller: controller),
                    if (controller.showReplace)
                      SlideFindReplaceRow(
                        controller: controller,
                        compact: compact,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
