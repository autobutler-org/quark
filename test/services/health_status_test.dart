import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/health_service.dart';

void main() {
  group('HealthStatus.fromJson', () {
    test('reads the alert and per-core lists', () {
      final status = HealthStatus.fromJson({
        'alerts': ['disk usage high'],
        'cpuCorePercents': [40.0, 45, 41.0],
      });

      expect(status.alerts, ['disk usage high']);
      expect(status.cpuCorePercents, [40.0, 45.0, 41.0]);
    });

    test('applies defaults for missing fields', () {
      final status = HealthStatus.fromJson({});

      expect(status.healthy, isTrue);
      expect(status.alerts, isEmpty);
      expect(status.cpuPercent, 0);
      expect(status.cpuCorePercents, isEmpty);
      expect(status.memPercent, 0);
      expect(status.memUsedBytes, 0);
      expect(status.memTotalBytes, 0);
      expect(status.diskPercent, 0);
      expect(status.diskUsedBytes, 0);
      expect(status.diskTotalBytes, 0);
      expect(status.temperatureCelsius, 0);
      expect(status.hostname, '');
    });

    test('handles integer values for floating-point fields', () {
      final json = {
        'cpuPercent': 50,
        'memPercent': 70,
        'diskPercent': 80,
        'temperatureCelsius': 60,
      };

      final status = HealthStatus.fromJson(json);

      expect(status.cpuPercent, 50.0);
      expect(status.memPercent, 70.0);
      expect(status.diskPercent, 80.0);
      expect(status.temperatureCelsius, 60.0);
    });
  });
}
