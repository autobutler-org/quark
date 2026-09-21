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
/// The first tab starts selected. Which tab is showing is the view's own
/// visual state, kept by a [DefaultTabController]: nothing outside the view
/// depends on it.
///
/// It fills the height it is given, so it goes where the height is bounded,
/// such as a page scaffold's body, and each tab's content scrolls itself.
///
/// Key prefixes: `tab_<label>` on each tab, with the label turned into a slug
/// by the same rule as [QuarkSection.slug], so a tab labeled `Groups` is
/// `#tab_groups`.
///
/// ```dart
/// QuarkTabView(
///   tabs: [
///     QuarkTab(label: 'Accounts', child: ListView(children: accounts)),
///     QuarkTab(label: 'Groups', child: ListView(children: groups)),
///   ],
/// );
/// ```
class QuarkTabView extends StatelessWidget {
  /// Creates the view over [tabs].
  const QuarkTabView({required this.tabs, super.key});

  /// The tabs, in order. The first starts selected.
  final List<QuarkTab> tabs;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            labelColor: tokens.foreground,
            unselectedLabelColor: tokens.mutedForeground,
            indicatorColor: tokens.primary,
            dividerColor: tokens.border,
            tabs: [
              for (final tab in tabs)
                Tab(
                  key: ValueKey('tab_${QuarkSection.slug(tab.label)}'),
                  text: tab.label,
                ),
            ],
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.child]),
          ),
        ],
      ),
    );
  }
}
