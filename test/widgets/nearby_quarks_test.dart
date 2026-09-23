import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/host_dialog.dart';
import 'package:quark/widgets/nearby_quarks.dart';
import 'package:quark/widgets/quark_connect_form.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Quarks found on the network, in the forms that take an address
/// (#2312): tapping one fills the address in, and a platform with no browser
/// shows nothing but the manual form.
void main() {
  final quark = HostEntry(
    name: 'Quark on quark-2',
    hostAddress: 'https://quark-2.local',
  );
  const rowKey = ValueKey('discovered_quark_Quark on quark-2');

  Stream<List<HostEntry>> browse() => Stream.value([quark]);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  String fieldText(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  testWidgets('without a browser, nothing is listed', (tester) async {
    // The test VM is neither iOS nor Android, so the default browser is null,
    // as it is on the web.
    await pump(tester, NearbyQuarks(onSelect: (_) {}));

    expect(find.byType(DiscoveredQuarkList), findsNothing);
  });

  testWidgets('Add Quark fills the name and address from a found Quark', (
    tester,
  ) async {
    await pump(tester, HostDialog(isEdit: false, browse: browse));

    await tester.tap(find.byKey(rowKey));
    await tester.pump();

    final fields = find.byType(TextField);
    expect(fieldText(tester, fields.first), 'Quark on quark-2');
    expect(fieldText(tester, fields.last), 'https://quark-2.local');
  });

  testWidgets('Add Quark keeps a nickname already typed', (tester) async {
    await pump(tester, HostDialog(isEdit: false, browse: browse));

    await tester.enterText(find.byType(TextField).first, 'Cabin');
    await tester.tap(find.byKey(rowKey));
    await tester.pump();

    expect(fieldText(tester, find.byType(TextField).first), 'Cabin');
  });

  testWidgets('the connect form fills the address from a found Quark', (
    tester,
  ) async {
    await pump(
      tester,
      SingleChildScrollView(
        child: QuarkConnectForm(onConnected: () {}, browse: browse),
      ),
    );

    await tester.tap(find.byKey(rowKey));
    await tester.pump();

    expect(fieldText(tester, find.byType(TextField)), 'https://quark-2.local');
  });

  testWidgets('closing the form stops the browse', (tester) async {
    var canceled = false;
    final browser = StreamController<List<HostEntry>>(
      onCancel: () => canceled = true,
    );
    await pump(
      tester,
      NearbyQuarks(onSelect: (_) {}, browse: () => browser.stream),
    );

    await tester.pumpWidget(const SizedBox.shrink());

    expect(canceled, isTrue);
  });
}
