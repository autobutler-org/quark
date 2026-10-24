import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const reason = "This video's format can't be previewed on this device.";

  Widget slot(Widget child, double side) => Center(
    child: SizedBox(width: side, height: side, child: child),
  );

  testBothViewports('a format it cannot preview keeps the video glyph', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      slot(
        const QuarkThumbnailUnavailable(
          name: 'hevc-aac.mov',
          kind: QuarkFileKind.video,
          issue: ThumbnailIssue.unsupportedFormat,
          reason: reason,
        ),
        40,
      ),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.video_file_outlined), findsOneWidget);
    expect(find.byIcon(QuarkIcons.visibility_off_outlined), findsOneWidget);
    expect(
      find.byKey(const ValueKey('thumbnail_unavailable_hevc-aac.mov')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(reason), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (issue, badge) in [
    (ThumbnailIssue.unreadable, QuarkIcons.broken_image_outlined),
    (ThumbnailIssue.missing, QuarkIcons.help_outline),
    (ThumbnailIssue.loadFailed, QuarkIcons.cloud_off_outlined),
  ]) {
    testBothViewports('a ${issue.name} thumbnail has its own badge', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        slot(
          QuarkThumbnailUnavailable(
            name: 'beach.jpg',
            kind: QuarkFileKind.image,
            issue: issue,
            reason: 'Why ${issue.name}',
          ),
          40,
        ),
        size: size,
      );

      expect(find.byIcon(QuarkIcons.image_outlined), findsOneWidget);
      expect(find.byIcon(badge), findsOneWidget);
      for (final other in [
        QuarkIcons.visibility_off_outlined,
        QuarkIcons.broken_image_outlined,
        QuarkIcons.help_outline,
        QuarkIcons.cloud_off_outlined,
      ].where((icon) => icon != badge)) {
        expect(find.byIcon(other), findsNothing);
      }
      expect(find.bySemanticsLabel('Why ${issue.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testBothViewports('the label shows only where there is room for it', (
    tester,
    size,
  ) async {
    const placeholder = QuarkThumbnailUnavailable(
      name: 'clip.ts',
      kind: QuarkFileKind.video,
      issue: ThumbnailIssue.unsupportedFormat,
      reason: reason,
      label: 'No preview',
    );
    await pumpAt(tester, slot(placeholder, 40), size: size);
    expect(find.text('No preview'), findsNothing, reason: 'a list row');

    await pumpAt(tester, slot(placeholder, 160), size: size);
    expect(find.text('No preview'), findsOneWidget, reason: 'a grid tile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering shows the reason', (tester) async {
    await pumpAt(
      tester,
      slot(
        const QuarkThumbnailUnavailable(
          name: 'clip.mov',
          kind: QuarkFileKind.video,
          issue: ThumbnailIssue.unsupportedFormat,
          reason: reason,
        ),
        40,
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byType(QuarkThumbnailUnavailable)),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('a long-press still reaches the tile around it', (tester) async {
    var menus = 0;
    await pumpAt(
      tester,
      slot(
        GestureDetector(
          onLongPressStart: (_) => menus++,
          child: const QuarkThumbnailUnavailable(
            name: 'clip.mov',
            kind: QuarkFileKind.video,
            issue: ThumbnailIssue.unsupportedFormat,
            reason: reason,
          ),
        ),
        40,
      ),
    );
    await tester.longPress(find.byType(QuarkThumbnailUnavailable));
    await tester.pump();

    expect(menus, 1);
  });
}
