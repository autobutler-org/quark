import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/chat_failed_send_bar.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2603, #2605: Retry and Discard are labeled 48dp targets.
void main() {
  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('retry and discard are labeled 48dp targets at $size', (
      tester,
    ) async {
      setViewport(tester, size);
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ChatFailedSendBar(
                  id: 'pending_0',
                  text: 'see you at noon',
                  error: "Couldn't send the message.",
                  onRetry: () => log.add('retry'),
                  onDiscard: () => log.add('discard'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('chat_failed_send_retry_pending_0')),
      );
      await tester.tap(
        find.byKey(const ValueKey('chat_failed_send_discard_pending_0')),
      );
      expect(log, ['retry', 'discard']);
      await expectTapTargetGuidelines(tester);
    });
  }

  testWidgets(
    'a failed row shows its indicator and actions, and a pending row shows sending',
    (tester) async {
      setViewport(tester, wideViewport);
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: Column(
              children: [
                ChatFailedSendBar(
                  id: 'pending_0',
                  text: 'first',
                  error: "Couldn't send the message.",
                  onRetry: () => log.add('retry-0'),
                  onDiscard: () => log.add('discard-0'),
                ),
                ChatFailedSendBar(
                  id: 'pending_1',
                  text: 'second',
                  onRetry: () => log.add('retry-1'),
                  onDiscard: () => log.add('discard-1'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('chat_send_failed_pending_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_failed_send_retry_pending_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_failed_send_discard_pending_0')),
        findsOneWidget,
      );
      expect(find.textContaining("Couldn't send the message."), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_send_sending_pending_1')),
        findsOneWidget,
      );
      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(find.textContaining('Sending "second"'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_failed_send_retry_pending_1')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('chat_failed_send_retry_pending_0')),
      );
      expect(log, ['retry-0']);

      // The sending indicator animates. Unmount it before the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
