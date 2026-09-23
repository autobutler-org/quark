import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Quarks found on the local network (#2312): each row hands back the Quark
/// it names, and an empty list says whether the search is still going.
void main() {
  const quarks = [
    HostItem(name: 'Quark on quark', address: 'https://quark.local'),
    HostItem(name: 'Quark on quark-2', address: 'https://quark-2.local'),
  ];

  testBothViewports('shows a searching line while nothing is found yet', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const DiscoveredQuarkList(quarks: [], isLoading: true),
      size: size,
    );

    expect(
      find.byKey(const ValueKey('discovered_quark_searching')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('discovered_quark_none')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('says so when the search found nothing', (
    tester,
    size,
  ) async {
    await pumpAt(tester, const DiscoveredQuarkList(quarks: []), size: size);

    expect(find.byKey(const ValueKey('discovered_quark_none')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const DiscoveredQuarkList(quarks: [], isLoading: true, error: 'Nope.'),
      size: size,
    );

    expect(find.text('Nope.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discovered_quark_searching')),
      findsNothing,
    );
  });

  testBothViewports('rows show while the search is still going', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const DiscoveredQuarkList(quarks: quarks, isLoading: true),
      size: size,
    );

    expect(find.text('https://quark-2.local'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discovered_quark_searching')),
      findsNothing,
    );
  });

  testBothViewports('hands back the Quark that was tapped', (
    tester,
    size,
  ) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      DiscoveredQuarkList(
        quarks: quarks,
        onSelect: (quark) => picked.add(quark.address),
      ),
      size: size,
    );

    await tester.tap(
      find.byKey(const ValueKey('discovered_quark_Quark on quark-2')),
    );
    await tester.pump();

    expect(picked, ['https://quark-2.local']);
    expect(tester.takeException(), isNull);
  });
}
