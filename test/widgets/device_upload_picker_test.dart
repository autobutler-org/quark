import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/device_upload_picker.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #3192: the upload sheet starts on the device it is told to, so the last
/// destination is one tap away.
void main() {
  const builtIn = UploadTarget(serial: '', name: 'Built-in', isInternal: true);
  const stick = UploadTarget(serial: 'USB1', name: 'Stick');

  /// Opens the sheet starting on [initial], confirms it untouched, and
  /// returns what it answered.
  Future<UploadTarget?> confirmUntouched(
    WidgetTester tester, {
    UploadTarget? initial,
  }) async {
    UploadTarget? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showDeviceUploadPicker(
              context,
              const [builtIn, stick],
              initial: initial,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('upload_target_confirm')));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('starts on the device it is given', (tester) async {
    expect(await confirmUntouched(tester, initial: stick), stick);
  });

  testWidgets('starts on the first device when given none', (tester) async {
    expect(await confirmUntouched(tester), builtIn);
  });

  // #3194: the sheet opens on a plain upload only when there is no default
  // device, and says so.
  testWidgets('shows the notice it is given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeviceUploadPicker(context, const [
              builtIn,
              stick,
            ], notice: 'No default.'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No default.'), findsOneWidget);
  });
}
