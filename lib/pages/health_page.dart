import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/widgets/health/health_body.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  HealthStatus? _status;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;

  @override
  Duration? get refreshInterval => const Duration(seconds: 15);

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
      debugPrint('[health_page.dart] Error: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Health',
        icon: QuarkIcons.monitor_heart_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
          ),
          const AppThemeToggle(),
        ],
      ),
      drawer: QuarkDrawer(
        activeSection: QuarkDrawerSection.health,
        onTapFiles: () {
          context.go(AppRoutes.files);
        },
        onTapPhotos: () {
          context.go(AppRoutes.photos);
        },
        onTapTrash: () => context.go(AppRoutes.trash),
        onTapDocs: () {
          context.go(AppRoutes.docs);
        },
        onTapSheets: () {
          context.go(AppRoutes.sheets);
        },
        onTapDevices: () {
          context.go(AppRoutes.devices);
        },
        onTapHealth: () {
          Navigator.of(context).pop();
        },
        onTapVault: () {
          context.go(AppRoutes.vault);
        },
        onTapSettings: () {
          context.go(AppRoutes.settings);
        },
      ),
      body: HealthBody(
        status: _status,
        error: _error,
        isInitialLoad: isInitialLoad,
        onRetry: manualRefresh,
        onManageHosts: () => context.go(AppRoutes.settings),
      ),
    );
  }
}
