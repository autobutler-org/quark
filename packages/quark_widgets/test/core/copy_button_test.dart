import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('hands the text to onCopy when tapped', (tester) async {
    final copied = <String>[];
    await pumpAt(
      tester,
      CopyButton(text: 'secret', onCopy: (v) async => copied.add(v)),
    );

    await tester.tap(find.byKey(const ValueKey('copy_button')));
    await tester.pump();

    expect(copied, ['secret']);
  });

  testWidgets('renders the labeled variant', (tester) async {
    await pumpAt(
      tester,
      CopyButton(
        text: 'secret',
        label: 'Copy phrase',
        variant: CopyButtonVariant.outlined,
        onCopy: (_) async {},
      ),
    );

    expect(find.text('Copy phrase'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('disables itself when the app says copying is impossible', (
    tester,
  ) async {
    var calls = 0;
    await pumpAt(
      tester,
      CopyButton(
        text: 'secret',
        unavailableReason: 'Use HTTPS to enable',
        onCopy: (_) async => calls++,
      ),
      size: narrowViewport,
    );

    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(find.byTooltip('Use HTTPS to enable'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('falls back to a generic label on the outlined variant', (
    tester,
  ) async {
    await pumpAt(
      tester,
      CopyButton(
        text: 'secret',
        variant: CopyButtonVariant.outlined,
        onCopy: (_) async {},
      ),
      size: wideViewport,
    );

    expect(find.text('Copy to clipboard'), findsOneWidget);
  });
}
