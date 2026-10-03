import 'package:flutter/material.dart';
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

      await tester.tap(find.byKey(const ValueKey('chat_failed_send_retry')));
      await tester.tap(find.byKey(const ValueKey('chat_failed_send_discard')));
      expect(log, ['retry', 'discard']);
      await expectTapTargetGuidelines(tester);
    });
  }
}
