import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/health/health_body.dart';

/// The System page's Health tab: the Quark's live device metrics, refreshed
/// every 15 seconds while the tab is on screen.
class HealthTab extends StatefulWidget {
  const HealthTab({this.onRefreshingChanged, super.key});

  /// Called with whether a refresh is in flight whenever that changes, so
  /// the page's app bar can show it.
  final ValueChanged<bool>? onRefreshingChanged;

  @override
  State<HealthTab> createState() => _HealthTabState();
}

class _HealthTabState extends State<HealthTab>
    with WidgetsBindingObserver, AutoRefreshMixin {
  HealthStatus? _status;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;

  @override
  Duration? get refreshInterval => const Duration(seconds: 15);

  @override
  void didChangeRefreshing() => widget.onRefreshingChanged?.call(isRefreshing);

  @override
  Future<void> refresh() async {
    if (AppSettings.instance.activeHost == null) {
      setState(() {
        _status = null;
        _error = null;
      });
      return;
    }
    try {
      final status = await HealthService.getHealth();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } catch (e) {
      debugPrint('[health_tab.dart] Error: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HealthBody(
      status: _status,
      error: _error,
      isInitialLoad: isInitialLoad,
      onRetry: manualRefresh,
      onManageHosts: () =>
          context.go(AppRoutes.settingsTab(SettingsTab.general)),
    );
  }
}
