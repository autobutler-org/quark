import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/health_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/health/health_severity.dart';
import 'package:quark/widgets/health/metric_card.dart';
import 'package:quark/widgets/health/status_banner.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Body of the health page: no host, spinner, error, or the metric list.
class HealthBody extends StatelessWidget {
  const HealthBody({
    required this.status,
    required this.error,
    required this.isInitialLoad,
    required this.onRetry,
    required this.onManageHosts,
    super.key,
  });

  final HealthStatus? status;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;
  final bool isInitialLoad;
  final VoidCallback onRetry;
  final VoidCallback onManageHosts;

  @override
  Widget build(BuildContext context) {
    if (AppSettings.instance.activeHost == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No backend host configured.\nAdd one in Settings.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
          onManageHosts: onManageHosts,
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                QuarkIcons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                Errors.somethingWentWrong,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                Errors.message(error, 'load health info'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(QuarkIcons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final status = this.status;
    if (status == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusBanner(
          severity: overallHealthSeverity(status),
          alerts: status.alerts,
        ),
        const SizedBox(height: 16),
        const Text(
          'System',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        MetricCard(
          label: 'CPU',
          icon: QuarkIcons.memory,
          value: status.cpuPercent,
          unit: '%',
          criticalThreshold: healthCpuCriticalPercent,
          detail: status.cpuCorePercents.isNotEmpty
              ? '${(status.cpuPercent / 100 * status.cpuCorePercents.length).toStringAsFixed(1)} of ${status.cpuCorePercents.length} cores'
              : null,
          corePercents: status.cpuCorePercents.isNotEmpty
              ? status.cpuCorePercents
              : null,
        ),
        const SizedBox(height: 8),
        MetricCard(
          label: 'Memory',
          icon: QuarkIcons.storage,
          value: status.memPercent,
          unit: '%',
          criticalThreshold: healthMemoryCriticalPercent,
          detail:
              '${_formatBytes(status.memUsedBytes)} used of ${_formatBytes(status.memTotalBytes)}',
        ),
        const SizedBox(height: 8),
        MetricCard(
          label: 'Disk',
          icon: QuarkIcons.disc_full,
          value: status.diskPercent,
          unit: '%',
          criticalThreshold: healthDiskCriticalPercent,
          detail:
              '${_formatBytes(status.diskUsedBytes)} used of ${_formatBytes(status.diskTotalBytes)}',
        ),
        if (status.temperatureCelsius > 0) ...[
          const SizedBox(height: 8),
          MetricCard(
            label: 'Temperature',
            icon: QuarkIcons.thermostat,
            value: status.temperatureCelsius,
            unit: '°C',
            criticalThreshold: healthTemperatureCriticalCelsius,
            maxValue: 100,
          ),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double val = bytes.toDouble();
  while (val >= 1024 && i < units.length - 1) {
    val /= 1024;
    i++;
  }
  return '${val.toStringAsFixed(1)} ${units[i]}';
}
