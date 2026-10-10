import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/widgets/settings/connected_devices_card.dart';

/// #2051: Connected devices listed `::1`, a raw User-Agent and a request
/// count per row. Each row now names the client, the caller's own row reads
/// "This browser", and removing a row asks first.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  const chromeMac =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  const safariPhone =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
      'Safari/604.1';
  const dartClient = 'Dart/3.5 (dart:io)';

  ConnectedDevice device(
    int id,
    String ipAddress,
    String userAgent, {
    bool current = false,
  }) {
    final seen = DateTime.now();
    return ConnectedDevice(
      id: id,
      ipAddress: ipAddress,
      userAgent: userAgent,
      firstSeenAt: seen,
      lastSeenAt: seen,
      requestCount: 1204,
      current: current,
    );
  }

  final devices = [
    device(1, '::1', chromeMac, current: true),
    device(2, '192.168.1.24', safariPhone),
    device(3, '127.0.0.1', dartClient),
  ];

  Finder removeButton(int id) =>
      find.byKey(ValueKey('connected_device_remove_$id'));

  /// Pumps the card and opens it, returning the ids [onRemove] was given.
  Future<List<int>> pumpCard(
    WidgetTester tester, {
    List<ConnectedDevice>? shown,
    bool isAdmin = true,
    Size size = wideViewport,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final removed = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectedDevicesCard(
              devices: shown ?? devices,
              isLoading: false,
              error: null,
              disconnected: false,
              isAdmin: isAdmin,
              onRefresh: () {},
              onRemove: removed.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Client connections'));
    await tester.pumpAndSettle();
    return removed;
  }

  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('names each device and shows no address or agent ($name)', (
      tester,
    ) async {
      await pumpCard(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(find.text('This browser'), findsOneWidget);
      expect(
        find.text('Chrome on macOS · last active just now'),
        findsOneWidget,
      );
      expect(find.text('Safari on iPhone'), findsOneWidget);
      expect(find.text('Quark app'), findsOneWidget);
      expect(find.text('Last active just now'), findsNWidgets(2));
      for (final raw in ['::1', '127.0.0.1', '192.168', 'Mozilla', 'request']) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
    });
  }

  testWidgets('the app marks its own row "This device"', (tester) async {
    await pumpCard(
      tester,
      shown: [device(3, '127.0.0.1', dartClient, current: true)],
    );

    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Quark app · last active just now'), findsOneWidget);
  });

  testWidgets('an admin can remove every row but their own', (tester) async {
    await pumpCard(tester);

    // The request that removes a row records the caller again.
    expect(removeButton(1), findsNothing);
    expect(removeButton(2), findsOneWidget);
    expect(removeButton(3), findsOneWidget);
  });

  testWidgets('a member has nothing to remove', (tester) async {
    await pumpCard(tester, isAdmin: false);

    expect(find.byKey(const ValueKey('connected_device_tile_2')), findsOne);
    expect(removeButton(2), findsNothing);
  });

  testWidgets('removing a device asks first', (tester) async {
    final removed = await pumpCard(tester);

    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    expect(find.text('Remove Safari on iPhone?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);

    await tester.tap(removeButton(2));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(removed, [2]);
  });
}
