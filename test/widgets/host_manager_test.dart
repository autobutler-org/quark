import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/host_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/text_scale.dart';

/// #2276: a right-click on a saved Quark in Settings opens the menu its
/// three-dot button does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  List<String> entries(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PopupMenuItem<int>),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data!)
      .toList();

  testWidgets('a right-click on a Quark opens Edit and Remove', (tester) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'https://home.local'},
        {'name': 'Cabin', 'hostAddress': 'https://cabin.local'},
      ]),
    });
    await AppSettings.instance.load();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HostManager())),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('host_menu_1')));
    await tester.pumpAndSettle();
    final fromButton = entries(tester);
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.text('Cabin')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(entries(tester), fromButton);
    expect(fromButton, ['Edit', 'Remove']);
    expect(
      find.byKey(const ValueKey('host_action_remove_1')),
      findsOneWidget,
      reason: 'the menu is for the row that was clicked',
    );
  });
  // #2603, #2605, #2606: each saved Quark is a radio a screen reader names,
  // and the list survives 200% text.
  testLargeText('every Quark is a labeled radio', (tester, _) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'https://home.local'},
        {'name': 'Cabin', 'hostAddress': 'https://cabin.local'},
      ]),
    });
    await AppSettings.instance.load();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: HostManager(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byKey(const ValueKey('host_row_1')),
          matching: find.byType(ListTile),
        ),
      ),
      isSemantics(
        label: 'Cabin\nhttps://cabin.local',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
  });
}
