import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_section.dart';

/// One tab of a [QuarkTabView]: the label on the tab and the content it
/// shows.
@immutable
class QuarkTab {
  /// Creates a tab labeled [label] showing [child].
  const QuarkTab({required this.label, required this.child});

  /// The text on the tab. Also the source of the tab's key.
  final String label;

  /// What the tab shows while it is selected.
  final Widget child;
}

/// A row of tabs over the content of the selected one, for a page split into
/// a few views of the same subject, like the accounts and groups on the Users
/// page.
///
/// Left alone, the view keeps the selected tab itself and the first tab
/// starts selected. A page whose tab is part of its URL controls it instead:
/// it passes [selectedIndex] in and hears about every change, a tap or a
/// swipe, through [onTabSelected]. When [selectedIndex] changes from outside,
/// such as the browser's back button, the view moves to that tab without
/// calling back.
///
/// It fills the height it is given, so it goes where the height is bounded,
/// such as a page scaffold's body, and each tab's content scrolls itself.
/// When the labels do not fit the width side by side, as five tabs do not on
/// a phone, the bar scrolls sideways instead.
///
/// Under reduced motion, when either `MediaQuery.disableAnimationsOf` (Android's
/// "Remove animations", the browser's `prefers-reduced-motion`) or the
/// platform's `accessibilityFeatures.reduceMotion` (iOS Reduce Motion) is set,
/// a tap or a new [selectedIndex] switches tabs at once instead of sliding the
/// indicator and the content across. A swipe still follows the finger.
///
/// Key prefixes: `tab_<label>` on each tab, with the label turned into a slug
/// by the same rule as [QuarkSection.slug], so a tab labeled `Groups` is
/// `#tab_groups`.
///
/// ```dart
/// QuarkTabView(
///   selectedIndex: tab.index,
///   onTabSelected: (index) => onTabSelected(UsersTab.values[index]),
///   tabs: [
///     QuarkTab(label: 'Accounts', child: ListView(children: accounts)),
///     QuarkTab(label: 'Groups', child: ListView(children: groups)),
///   ],
/// );
/// ```
class QuarkTabView extends StatefulWidget {
  /// Creates the view over [tabs].
  const QuarkTabView({
    required this.tabs,
    this.selectedIndex,
    this.onTabSelected,
    super.key,
  });

  /// The tabs, in order.
  final List<QuarkTab> tabs;

  /// The index into [tabs] of the tab to show. Null lets the view keep it,
  /// starting on the first tab.
  final int? selectedIndex;

  /// Called with the index of a tab the user picked, by tapping it or by
  /// swiping to it. Not called when [selectedIndex] moves the view.
  final ValueChanged<int>? onTabSelected;

  @override
  State<QuarkTabView> createState() => _QuarkTabViewState();
}

class _QuarkTabViewState extends State<QuarkTabView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  TabController? _controller;
  bool? _reduceMotion;

  /// The index last reported or set from outside, so a change is reported
  /// once and a change the caller made is not reported back to it.
  late int _reported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(_updateMotion);

  /// A [TabController]'s animation duration is fixed when it is made, and it
  /// times the tab bar's indicator and the view's page slide alike, so a
  /// change in reduced motion replaces the controller, keeping the tab.
  void _updateMotion() {
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _replaceController(_controller?.index ?? widget.selectedIndex ?? 0);
  }

  void _replaceController(int index) {
    _controller?.dispose();
    _reported = index.clamp(0, widget.tabs.length - 1);
    _controller = TabController(
      length: widget.tabs.length,
      initialIndex: _reported,
      animationDuration: _reduceMotion! ? Duration.zero : null,
      vsync: this,
    )..addListener(_onIndexChanged);
  }

  void _onIndexChanged() {
    final index = _controller!.index;
    if (index == _reported) return;
    _reported = index;
    widget.onTabSelected?.call(index);
  }

  @override
  void didUpdateWidget(QuarkTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabs.length != oldWidget.tabs.length) {
      _replaceController(widget.selectedIndex ?? 0);
      return;
    }
    final selected = widget.selectedIndex;
    if (selected == null || selected == _controller!.index) return;
    _reported = selected;
    _controller!.animateTo(selected);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final labelStyle =
        TabBarTheme.of(context).labelStyle ??
        Theme.of(context).textTheme.titleSmall;
    final textScaler = MediaQuery.textScalerOf(context);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final labelsWidth = widget.tabs.fold<double>(
              0,
              (sum, tab) =>
                  sum +
                  _labelWidth(tab.label, labelStyle, textScaler) +
                  kTabLabelPadding.horizontal,
            );
            final scrolls = labelsWidth > constraints.maxWidth;
            return TabBar(
              controller: _controller!,
              isScrollable: scrolls,
              tabAlignment: scrolls ? TabAlignment.start : null,
              labelColor: tokens.foreground,
              unselectedLabelColor: tokens.mutedForeground,
              indicatorColor: tokens.primary,
              dividerColor: tokens.border,
              tabs: [
                for (final tab in widget.tabs)
                  Tab(
                    key: ValueKey('tab_${QuarkSection.slug(tab.label)}'),
                    text: tab.label,
                  ),
              ],
            );
          },
        ),
        Expanded(
          child: TabBarView(
            controller: _controller!,
            children: [for (final tab in widget.tabs) tab.child],
          ),
        ),
      ],
    );
  }
}

/// How wide [label] is on one line in [style].
double _labelWidth(String label, TextStyle? style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
