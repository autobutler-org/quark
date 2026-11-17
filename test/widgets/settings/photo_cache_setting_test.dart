import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/settings/photo_cache_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/secure_storage.dart';

/// #4221: Settings shows how much the photo cache holds and empties it.
/// `photo_disk_cache_test.dart` covers what clearing does on disk.
void main() {
  setUpAll(() => mockSecureStorage({}));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Future<int> Function() sizeInBytes,
    Future<void> Function()? clear,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PhotoCacheSetting(
              sizeInBytes: sizeInBytes,
              clear: clear ?? () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('"Clear cached photos" empties the cache', (tester) async {
    var used = 2048;
    var cleared = 0;
    await pump(
      tester,
      sizeInBytes: () async => used,
      clear: () async {
        cleared++;
        used = 0;
      },
    );
    expect(find.textContaining('Now using 2.0 KB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_photo_cache_clear')));
    await tester.pumpAndSettle();

    expect(cleared, 1);
    expect(find.textContaining('Now using 0 B'), findsOneWidget);
  });

  testWidgets('the button is off while nothing is cached', (tester) async {
    await pump(tester, sizeInBytes: () async => 0);

    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('settings_photo_cache_clear')),
    );
    expect(button.onPressed, isNull);
  });
}
