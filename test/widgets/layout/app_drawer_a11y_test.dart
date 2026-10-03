import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/text_scale.dart';

/// #2606, #2603, #2605: the drawer every page opens, and the bar controls
/// every page carries, survive 200% text on a phone and a desktop with every
/// row labeled and big enough to hit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.instance;
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

  setUp(() {
    // An admin with every beta on, so the drawer holds every row it can.
    settings.isAdmin.value = true;
    settings.featureFlags.value = [
      for (final key in [FeatureFlag.chat])
        FeatureFlag(key: key, label: key, description: '', enabled: true),
    ];
  });

  tearDown(() {
    settings.isAdmin.value = false;
    settings.featureFlags.value = const [];
  });

  testLargeText('the drawer lays out top to bottom', (tester, _) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          key: scaffold,
          appBar: QuarkAppBar(
            label: 'Files',
            icon: QuarkIcons.folder_rounded,
            actions: const [AppThemeToggle()],
          ),
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.files),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    final list = find
        .descendant(
          of: find.byType(AppDrawer),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 20; i++) {
      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
      final position = tester.state<ScrollableState>(list).position;
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(position.pixels + position.viewportDimension * 0.8);
      await tester.pump();
    }
  });
}
