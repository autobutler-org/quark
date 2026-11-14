import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one playback speed picker behind the video and audio controls
/// (#4103).
void main() {
  const menuKey = ValueKey('speed_menu');

  testBothViewports('shows the current speed', (tester, size) async {
    await pumpAt(
      tester,
      Center(
        child: QuarkPlaybackSpeedMenu(
          key: menuKey,
          speed: 1.25,
          onSelected: (_) {},
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1.25x'), findsOneWidget);
  });

  testBothViewports('opens the six speeds, current one marked', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Center(
        child: QuarkPlaybackSpeedMenu(
          key: menuKey,
          speed: 1.5,
          onSelected: (_) {},
        ),
      ),
      size: size,
    );

    await tester.tap(find.byKey(menuKey));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final s in QuarkPlaybackSpeedMenu.speeds) {
      expect(find.byKey(ValueKey('playback_speed_$s')), findsOneWidget);
    }
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('2.0x'), findsOneWidget);
    final popup = tester.widget<PopupMenuButton<double>>(
      find.byType(PopupMenuButton<double>),
    );
    expect(popup.initialValue, 1.5);
  });

  testWidgets('reports the pick once', (tester) async {
    final picked = <double>[];
    await pumpAt(
      tester,
      Center(
        child: QuarkPlaybackSpeedMenu(
          key: menuKey,
          speed: 1.0,
          onSelected: picked.add,
        ),
      ),
    );

    await tester.tap(find.byKey(menuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playback_speed_0.75')));
    await tester.pumpAndSettle();

    expect(picked, [0.75]);
  });

  testWidgets('takes the caller text style', (tester) async {
    await pumpAt(
      tester,
      QuarkPlaybackSpeedMenu(
        speed: 2.0,
        onSelected: (_) {},
        textStyle: const TextStyle(color: Colors.white),
      ),
    );

    expect(tester.widget<Text>(find.text('2.00x')).style?.color, Colors.white);
  });
}
