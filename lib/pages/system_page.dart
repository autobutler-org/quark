import 'package:flutter/material.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/system/health_tab.dart';
import 'package:quark/widgets/system/jobs_tab.dart';
import 'package:quark/widgets/system/storage_tab.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page (#2351): the Quark itself, in three tabs. **Health** has
/// its live metrics, **Storage** the drives it can see, and **Jobs** the work
/// on its queue. They were three pages before.
///
/// Each tab has its own URL: the router passes the [tab] to show and
/// [onTabSelected] to move to another. Each tab loads and refreshes itself,
/// and only the one on screen is built, so Health stops polling once the
/// user moves to another tab. The app bar's refresh slot drives the tab on
/// screen.
class SystemPage extends StatefulWidget {
  const SystemPage({
    this.tab = SystemTab.health,
    this.onTabSelected,
    super.key,
  });

  /// The tab to show.
  final SystemTab tab;

  /// Called with the tab the user picked. Null keeps the choice in the view.
  final ValueChanged<SystemTab>? onTabSelected;

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  final _tabs = {
    for (final tab in SystemTab.values) tab: GlobalKey<AutoRefreshMixin>(),
  };
  final _refreshing = <SystemTab, bool>{};

  /// Records whether [tab] is refreshing. A tab reports from its initState,
  /// in the middle of this page's build, so the change waits for the frame.
  void _onRefreshingChanged(SystemTab tab, bool refreshing) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _refreshing[tab] = refreshing);
    });
  }

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'System',
      icon: QuarkIcons.memory,
      onRefresh: () => _tabs[widget.tab]!.currentState?.manualRefresh(),
      isRefreshing: _refreshing[widget.tab] ?? false,
      actions: const [AppThemeToggle()],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.system),
      body: QuarkTabView(
        selectedIndex: widget.tab.index,
        onTabSelected: widget.onTabSelected == null
            ? null
            : (index) => widget.onTabSelected!(SystemTab.values[index]),
        tabs: [
          QuarkTab(
            label: 'Health',
            child: HealthTab(
              key: _tabs[SystemTab.health],
              onRefreshingChanged: (r) =>
                  _onRefreshingChanged(SystemTab.health, r),
            ),
          ),
          QuarkTab(
            label: 'Storage',
            child: StorageTab(
              key: _tabs[SystemTab.storage],
              onRefreshingChanged: (r) =>
                  _onRefreshingChanged(SystemTab.storage, r),
            ),
          ),
          QuarkTab(
            label: 'Jobs',
            child: JobsTab(
              key: _tabs[SystemTab.jobs],
              onRefreshingChanged: (r) =>
                  _onRefreshingChanged(SystemTab.jobs, r),
            ),
          ),
        ],
      ),
    );
  }
}
