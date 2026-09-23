import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/quark_discovery_controller.dart';
import 'package:quark/services/app_settings.dart';

/// The state behind the Quarks found on the network (#2312), driven by a fake
/// browser.
void main() {
  late StreamController<List<HostEntry>> browser;
  late bool canceled;

  setUp(() {
    canceled = false;
    browser = StreamController<List<HostEntry>>(
      onCancel: () => canceled = true,
    );
  });

  test('lists what the browser finds, as it finds it', () async {
    final controller = QuarkDiscoveryController(browse: () => browser.stream);
    addTearDown(controller.dispose);
    expect(controller.isSearching, isTrue);
    expect(controller.quarks, isEmpty);

    final quark = HostEntry(
      name: 'Quark on quark',
      hostAddress: 'https://quark.local',
    );
    browser.add([quark]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.quarks, [quark]);
  });

  test('stops reading as searching once the window passes', () async {
    final controller = QuarkDiscoveryController(
      browse: () => browser.stream,
      searchWindow: Duration.zero,
    );
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(controller.isSearching, isFalse);
  });

  test('a failed browse keeps its error and stops searching', () async {
    final controller = QuarkDiscoveryController(browse: () => browser.stream);
    addTearDown(controller.dispose);

    browser.addError(Exception('no multicast'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.error, isA<Exception>());
    expect(controller.isSearching, isFalse);
  });

  test('dispose stops the browse', () async {
    final controller = QuarkDiscoveryController(browse: () => browser.stream);

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(canceled, isTrue);
  });
}
