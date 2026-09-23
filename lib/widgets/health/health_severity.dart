import 'package:quark/services/health_service.dart';

/// How severe the health page's summary should be.
///
/// [healthy] is calm, [warning] is the orange band, and [critical] is a red
/// reading or a backend alert. [overallHealthSeverity] returns the highest
/// one present.
enum HealthSeverity {
  /// Every meter and core is under its warning line, and the Quark reports
  /// no alert.
  healthy,

  /// A meter or CPU core is in the orange band, and nothing is critical.
  warning,

  /// A meter or core is at its red line, or the Quark reported an alert.
  critical,
}

/// CPU percent at which the meter and the summary turn critical.
const double healthCpuCriticalPercent = 90;

/// Memory percent at which the meter and the summary turn critical.
const double healthMemoryCriticalPercent = 95;

/// Disk percent at which the meter and the summary turn critical.
const double healthDiskCriticalPercent = 90;

/// Celsius at which the temperature meter and the summary turn critical.
///
/// A reading that is not positive means no sensor, so it is not scored.
const double healthTemperatureCriticalCelsius = 80;

/// Per-core percent at which a chip and the summary turn critical.
const double healthCoreCriticalPercent = 90;

/// Per-core percent at which a chip and the summary turn warning.
///
/// 67, not 67.5. The aggregate CPU meter warns at [healthWarningFraction] of
/// [healthCpuCriticalPercent]; the chips use this whole-number line instead.
const double healthCoreWarningPercent = 67;

/// Fraction of a meter's critical line where orange, and a warning, starts.
///
/// The metric card paints its orange band at this same fraction.
const double healthWarningFraction = 0.75;

/// Worst severity across the health meters, each CPU core, and any backend
/// alert.
///
/// CPU, memory, and disk turn critical at [healthCpuCriticalPercent],
/// [healthMemoryCriticalPercent], and [healthDiskCriticalPercent], and turn
/// warning at [healthWarningFraction] of those lines — the same orange band
/// the metric card paints. Temperature counts only when
/// [HealthStatus.temperatureCelsius] is positive, critical at
/// [healthTemperatureCriticalCelsius]. Each core is critical at
/// [healthCoreCriticalPercent] and warning at [healthCoreWarningPercent],
/// matching the per-core chips. A non-empty [HealthStatus.alerts] list, or
/// [HealthStatus.healthy] set to false, is critical on its own, so a backend
/// alert is never hidden behind calm percentages. The highest severity
/// present wins.
HealthSeverity overallHealthSeverity(HealthStatus status) {
  var worst = HealthSeverity.healthy;
  worst = _higherSeverity(
    worst,
    _meterSeverity(status.cpuPercent, healthCpuCriticalPercent),
  );
  worst = _higherSeverity(
    worst,
    _meterSeverity(status.memPercent, healthMemoryCriticalPercent),
  );
  worst = _higherSeverity(
    worst,
    _meterSeverity(status.diskPercent, healthDiskCriticalPercent),
  );
  if (status.temperatureCelsius > 0) {
    worst = _higherSeverity(
      worst,
      _meterSeverity(
        status.temperatureCelsius,
        healthTemperatureCriticalCelsius,
      ),
    );
  }
  for (final core in status.cpuCorePercents) {
    worst = _higherSeverity(worst, _coreSeverity(core));
  }
  if (!status.healthy || status.alerts.isNotEmpty) {
    worst = _higherSeverity(worst, HealthSeverity.critical);
  }
  return worst;
}

/// Meter severity: critical at [criticalAt], warning at
/// [healthWarningFraction] of that line, otherwise healthy.
HealthSeverity _meterSeverity(double value, double criticalAt) {
  if (value >= criticalAt) return HealthSeverity.critical;
  if (value >= criticalAt * healthWarningFraction) {
    return HealthSeverity.warning;
  }
  return HealthSeverity.healthy;
}

/// Chip severity. Orange from [healthCoreWarningPercent], red from
/// [healthCoreCriticalPercent].
HealthSeverity _coreSeverity(double percent) {
  if (percent >= healthCoreCriticalPercent) return HealthSeverity.critical;
  if (percent >= healthCoreWarningPercent) return HealthSeverity.warning;
  return HealthSeverity.healthy;
}

/// The further-from-calm of [a] and [b].
HealthSeverity _higherSeverity(HealthSeverity a, HealthSeverity b) {
  if (a == HealthSeverity.critical || b == HealthSeverity.critical) {
    return HealthSeverity.critical;
  }
  if (a == HealthSeverity.warning || b == HealthSeverity.warning) {
    return HealthSeverity.warning;
  }
  return HealthSeverity.healthy;
}
