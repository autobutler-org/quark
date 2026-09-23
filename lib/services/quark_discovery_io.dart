import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/quark_discovery.dart';

/// The native browser on iOS and Android, where bonsoir browses mDNS. Null
/// on desktop.
///
/// On Android, bonsoir holds the Wi-Fi multicast lock while it browses and
/// merges `CHANGE_WIFI_MULTICAST_STATE` into the manifest itself.
QuarkBrowser? get quarkBrowser =>
    Platform.isIOS || Platform.isAndroid ? _browse : null;

Stream<List<HostEntry>> _browse() {
  final found = <String, HostEntry>{};
  BonsoirDiscovery? discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? events;
  var canceled = false;
  late final StreamController<List<HostEntry>> out;

  void onEvent(BonsoirDiscoveryEvent event) {
    final service = event.service;
    if (service == null) return;
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        service.resolve(discovery!.serviceResolver);
        return;
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final entry = discoveredQuark(
          name: service.name,
          host: service is ResolvedBonsoirService ? service.host : null,
          port: service.port,
        );
        if (entry == null) return;
        found[service.name] = entry;
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        if (found.remove(service.name) == null) return;
      default:
        return;
    }
    out.add(List.unmodifiable(found.values));
  }

  Future<void> start() async {
    try {
      final d = BonsoirDiscovery(type: quarkServiceType);
      discovery = d;
      await d.ready;
      if (canceled) return;
      events = d.eventStream!.listen(onEvent, onError: out.addError);
      await d.start();
    } catch (e, st) {
      if (!canceled) out.addError(e, st);
    }
  }

  Future<void> stop() async {
    canceled = true;
    await events?.cancel();
    try {
      await discovery?.stop();
    } catch (_) {
      // A browse canceled before it started has nothing to stop.
    }
  }

  out = StreamController<List<HostEntry>>(onListen: start, onCancel: stop);
  return out.stream;
}
