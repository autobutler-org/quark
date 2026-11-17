import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('wraps a long note without overflowing', (
    tester,
    size,
  ) async {
    const text =
        'Items here are deleted for good after 30 days. Restore puts each '
        'one back in the folder it came from.';
    await pumpAt(tester, const QuarkInfoNote(text: text), size: size);

    expect(tester.takeException(), isNull);
    expect(find.text(text), findsOneWidget);
    expect(find.byIcon(QuarkIcons.info_outline), findsOneWidget);
  });
}
