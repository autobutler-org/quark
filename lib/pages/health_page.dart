import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/health_service.dart';
import 'package:autobutler/utils/auto_refresh_mixin.dart';
import 'package:autobutler/widgets/layout/autobutler_app_bar.dart';
import 'package:autobutler/widgets/autobutler_drawer.dart';
import 'package:autobutler/widgets/refresh_icon_button.dart';
import 'package:autobutler/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  HealthStatus? _status;
  String? _error;

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
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutobutlerAppBar(
        label: 'Health',
        icon: Icons.monitor_heart_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
          ),
        ],
      ),
      drawer: AutobutlerDrawer(
        activeSection: AutobutlerDrawerSection.health,
        onTapCirrus: () {
          context.go(AppRoutes.cirrus);
        },
        onTapPhotos: () {
          context.go(AppRoutes.photos);
        },
        onTapDevices: () {
          context.go(AppRoutes.devices);
        },
        onTapHealth: () {
          Navigator.of(context).pop();
        },
        onTapSettings: () {
          context.go(AppRoutes.settings);
        },
        onTapPlugins: () {
          context.go(AppRoutes.plugins);
        },
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load health data',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: manualRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final status = _status;
    if (status == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBanner(healthy: status.healthy, alerts: status.alerts),
        const SizedBox(height: 16),
        const Text(
          'System',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _MetricCard(
          label: 'CPU',
          icon: Icons.memory,
          value: status.cpuPercent,
          unit: '%',
          criticalThreshold: 90,
          detail: status.cpuCorePercents.isNotEmpty
              ? '${(status.cpuPercent / 100 * status.cpuCorePercents.length).toStringAsFixed(1)} of ${status.cpuCorePercents.length} cores'
              : null,
          corePercents: status.cpuCorePercents.isNotEmpty
              ? status.cpuCorePercents
              : null,
        ),
        const SizedBox(height: 8),
        _MetricCard(
          label: 'Memory',
          icon: Icons.storage,
          value: status.memPercent,
          unit: '%',
          criticalThreshold: 95,
          detail:
              '${_formatBytes(status.memUsedBytes)} used of ${_formatBytes(status.memTotalBytes)}',
        ),
        const SizedBox(height: 8),
        _MetricCard(
          label: 'Disk',
          icon: Icons.disc_full,
          value: status.diskPercent,
          unit: '%',
          criticalThreshold: 90,
          detail:
              '${_formatBytes(status.diskUsedBytes)} used of ${_formatBytes(status.diskTotalBytes)}',
        ),
        if (status.temperatureCelsius > 0) ...[
          const SizedBox(height: 8),
          _MetricCard(
            label: 'Temperature',
            icon: Icons.thermostat,
            value: status.temperatureCelsius,
            unit: '°C',
            criticalThreshold: 80,
            maxValue: 100,
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.healthy, required this.alerts});

  final bool healthy;
  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    final color = healthy
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    final onColor = healthy
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onErrorContainer;
    final icon = healthy ? Icons.check_circle_outline : Icons.warning_amber;
    final label = healthy ? 'All systems healthy' : 'Issues detected';

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: onColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...alerts.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '• $a',
                    style: TextStyle(color: onColor, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.criticalThreshold,
    this.maxValue = 100,
    this.detail,
    this.corePercents,
  });

  final String label;
  final IconData icon;
  final double value;
  final String unit;
  final double criticalThreshold;
  final double maxValue;
  final String? detail;
  final List<double>? corePercents;

  Color _barColor(BuildContext context) {
    if (value >= criticalThreshold) return Theme.of(context).colorScheme.error;
    if (value >= criticalThreshold * 0.75) return Colors.orange;
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (value / maxValue).clamp(0.0, 1.0);
    final barColor = _barColor(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${value.toStringAsFixed(1)}$unit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: barColor,
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                color: barColor,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                minHeight: 8,
              ),
            ),
            if (corePercents != null && corePercents!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: () {
                  final total = corePercents!.fold(0.0, (s, v) => s + v);
                  return corePercents!.asMap().entries.map((e) {
                    final contribution = total > 0
                        ? (e.value / total * 100)
                        : 0.0;
                    final coreColor = e.value >= 90
                        ? Theme.of(context).colorScheme.error
                        : e.value >= 67
                        ? Colors.orange
                        : Theme.of(context).colorScheme.primary;
                    return Chip(
                      label: Text(
                        'Core ${e.key + 1}: ${e.value.toStringAsFixed(0)}% (${contribution.toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 11, color: coreColor),
                      ),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: coreColor.withValues(alpha: 0.4)),
                      backgroundColor: coreColor.withValues(alpha: 0.08),
                    );
                  }).toList();
                }(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
