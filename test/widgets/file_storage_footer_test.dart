import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_storage_footer.dart';
import 'package:quark_widgets/quark_widgets.dart';

// The footer is the last child of the file browser's Column, so it sits flush
// against the physical bottom edge — the band where iOS draws the home
// indicator and Android its gesture bar. It drew the storage readout and
// progress bar straight into that band (#1598).
//
// These pump the footer under a MediaQuery carrying real device insets. The
// health request fails in the test environment, which is fine: the footer is
// built to stay in its placeholder state when health is unreachable, and the
// layout is what's under test.
void main() {
  // iPhone 15 Pro portrait: 34pt home indicator band.
  const gestureInsets = EdgeInsets.only(top: 59, bottom: 34);
  // Same device rotated: shorter bottom band, insets on the sides.
  const landscapeInsets = EdgeInsets.only(left: 59, right: 59, bottom: 21);

  Future<double> pumpFooter(
    WidgetTester tester, {
    EdgeInsets insets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: insets, viewPadding: insets),
          child: Scaffold(
            body: Column(children: [const Spacer(), const FileStorageFooter()]),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.view.physicalSize.height / tester.view.devicePixelRatio;
  }

  testWidgets('keeps its contents above the bottom inset', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: gestureInsets);
    final safeBottom = screenHeight - gestureInsets.bottom;

    final controls = <String, Finder>{
      'the storage readout': find.text(kStorageFooterScope),
      'the progress bar': find.byType(QuarkStorageBar),
    };
    for (final entry in controls.entries) {
      expect(
        tester.getRect(entry.value).bottom,
        lessThanOrEqualTo(safeBottom),
        reason: '${entry.key} must clear the home indicator',
      );
    }
  });

  testWidgets('paints the bar through the inset region', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: gestureInsets);

    // The footer itself still reaches the physical bottom edge — only its
    // contents are lifted — so the home indicator sits on the footer's own
    // background instead of on bare page.
    final footer = tester.getRect(find.byType(FileStorageFooter));
    expect(footer.bottom, screenHeight);

    final content = tester.getRect(
      find
          .descendant(
            of: find.byType(FileStorageFooter),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(
      footer.bottom - content.bottom,
      greaterThanOrEqualTo(gestureInsets.bottom),
      reason: 'the painted band below the content has to cover the inset',
    );
  });

  testWidgets('honors the side insets in landscape', (
    WidgetTester tester,
  ) async {
    final screenHeight = await pumpFooter(tester, insets: landscapeInsets);

    expect(
      tester.getRect(find.byType(Icon)).left,
      greaterThanOrEqualTo(landscapeInsets.left),
    );
    expect(
      tester.getRect(find.text(kStorageFooterScope)).bottom,
      lessThanOrEqualTo(screenHeight - landscapeInsets.bottom),
    );
  });

  testWidgets('adds no padding on a device without insets', (
    WidgetTester tester,
  ) async {
    final withoutInsets = await pumpFooter(tester);
    final bare = tester.getRect(find.byType(FileStorageFooter)).height;
    expect(
      tester.getRect(find.byType(FileStorageFooter)).bottom,
      withoutInsets,
    );

    final screenHeight = await pumpFooter(tester, insets: gestureInsets);
    expect(screenHeight, withoutInsets);
    expect(
      tester.getRect(find.byType(FileStorageFooter)).height,
      bare + gestureInsets.bottom,
      reason: 'the inset is the only thing that grows the footer',
    );
  });

  /// #2024: the footer showed "38.7 GB / 125 GB" beside "No files yet" on a
  /// brand-new Quark, which reads as the appliance having eaten the disk
  /// before the owner put anything on it. The figure is the whole device, and
  /// now says so.
  testWidgets('names the scope of the figure it shows', (tester) async {
    await pumpFooter(tester);

    expect(find.textContaining(kStorageFooterScope), findsOneWidget);
    expect(find.byTooltip(kStorageFooterExplanation), findsOneWidget);
  });

  testWidgets('survives a phone-width bar with the scope in the label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpFooter(tester);

    expect(tester.takeException(), isNull);
  });
}
