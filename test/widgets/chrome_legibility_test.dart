import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/calendar/calendar_bar_bottom.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2740: under a picked theme color the app bar and the drawer are a
/// saturated surface of their own, so every text and icon the app draws on
/// them has to be legible there: 4.5:1 for text, 3:1 for an icon.
///
/// Each glyph is measured against the fill it is actually painted on: the
/// nearest filled ancestor inside the bar, blended down to the chrome. A
/// widget that reads `Theme.of(context).colorScheme` or a hardcoded color in
/// the bar fails here, because `QuarkChrome` does not remap either.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
    // Two Quarks, so the drawer shows its host switcher.
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': 'http://home.local'},
        {'name': 'Cabin', 'hostAddress': 'http://cabin.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    AppSettings.instance.isAdmin.value = true;
  });

  tearDownAll(() {
    AppSettings.instance.isAdmin.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  /// The opaque fill [element] is painted on: every filled ancestor up to
  /// [chrome]'s own surface, blended from the chrome up.
  Color fillBehind(Element element, Color chrome) {
    final fills = <Color>[];
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is AppBar || widget is Drawer) return false;
      final color = switch (widget) {
        ColoredBox(:final color) => color,
        DecoratedBox(decoration: BoxDecoration(:final color?)) => color,
        Ink(decoration: BoxDecoration(:final color?)) => color,
        Material(:final color?, :final type)
            when type != MaterialType.transparency =>
          color,
        _ => null,
      };
      if (color != null) fills.add(color);
      return color == null || color.a < 1;
    });
    return fills.reversed.fold(chrome, (under, fill) {
      return Color.alphaBlend(fill, under);
    });
  }

  /// Fails for every text and icon under [chromeSurface] that is not legible
  /// on the fill behind it.
  void expectLegible(WidgetTester tester, Finder chromeSurface) {
    final tokens = QuarkTokens.of(tester.element(chromeSurface));
    final glyphs = find.descendant(
      of: chromeSurface,
      matching: find.byType(RichText),
    );
    expect(glyphs, findsWidgets);
    final failures = <String>[];
    for (final element in glyphs.evaluate()) {
      final span = (element.widget as RichText).text;
      final color = span.style?.color;
      if (color == null) continue;
      final isIcon = element.findAncestorWidgetOfExactType<Icon>() != null;
      final fill = fillBehind(element, tokens.chrome);
      final ratio = contrastRatio(Color.alphaBlend(color, fill), fill);
      if (ratio < (isIcon ? 3 : 4.5)) {
        final what = isIcon ? 'icon' : '"${span.toPlainText()}"';
        failures.add('$what: $color on $fill is ${ratio.toStringAsFixed(2)}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }

  Future<void> pump(
    WidgetTester tester,
    ThemeData theme,
    PreferredSizeWidget appBar,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: appBar,
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.files),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final bars = <String, PreferredSizeWidget Function()>{
    'Files': () => FileTopBar(
      currentPath: '/docs/reports/2026',
      rootPath: '',
      isGridView: false,
      isUnifiedView: false,
      onToggleUnifiedView: () {},
      isSearchMode: false,
      isUploading: false,
      isCreatingFolder: false,
      isRefreshing: false,
      onGoHome: () {},
      onGoUp: () {},
      onToggleView: () {},
      onSearchChanged: (_) {},
      onSearchClosed: () {},
      onRefresh: () {},
      onUploadPressed: () {},
      onCreateFolderPressed: () {},
      onNewFilePressed: () {},
      onPathSelected: (_) {},
      onStartSelection: () {},
    ),
    'Calendar': () => QuarkAppBar(
      label: 'Calendar',
      icon: QuarkIcons.calendar_month_outlined,
      onRefresh: () {},
      actions: [
        QuarkBarChip(
          icon: QuarkIcons.add_rounded,
          label: 'New event',
          onPressed: () {},
        ),
        const AppThemeToggle(),
      ],
      bottom: CalendarBarBottom(
        view: CalendarBarBottom.order.first,
        anchor: DateTime(2026, 9, 29),
        days: [DateTime(2026, 9, 29)],
        onPrevious: () {},
        onNext: () {},
        onToday: () {},
        onViewSelected: (_) {},
      ),
    ),
    // A drill-down page: an editor's bar, with one action disabled.
    'an editor': () => ChromeAppBar(
      leading: const BackButton(),
      title: const Text('notes.txt'),
      actions: [
        const QuarkBarChip(
          icon: QuarkIcons.save_outlined,
          label: 'Save',
          onPressed: null,
        ),
        QuarkBarIconButton(
          icon: QuarkIcons.download_outlined,
          tooltip: 'Download',
          onPressed: () {},
        ),
        const AppThemeToggle(),
      ],
    ),
  };

  for (final themeColor in [QuarkThemeColor.violet, QuarkThemeColor.lime]) {
    final themes = {
      'light': QuarkTheme.light(themeColor: themeColor),
      'dark': QuarkTheme.dark(themeColor: themeColor),
    };
    for (final MapEntry(key: mode, value: theme) in themes.entries) {
      for (final MapEntry(key: name, value: bar) in bars.entries) {
        testWidgets('$name bar is legible in ${themeColor.name} $mode', (
          tester,
        ) async {
          await pump(tester, theme, bar());
          expectLegible(tester, find.byType(AppBar));
        });
      }

      testWidgets('the drawer is legible in ${themeColor.name} $mode', (
        tester,
      ) async {
        await pump(tester, theme, bars['Calendar']!());
        tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();
        expectLegible(tester, find.byType(Drawer));
      });
    }
  }
}
