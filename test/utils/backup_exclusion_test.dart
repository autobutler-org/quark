import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/backup_exclusion.dart';

/// #4221: on iOS the photo cache's folder is marked to stay out of iCloud
/// backup. `RunnerTests.testExcludeFromBackupSetsTheAttribute` checks the
/// native side sets the attribute; this checks the app asks it to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backupExclusionChannel, null);
  });

  test('iOS marks the folder to stay out of backup', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await excludeFromBackup('/Library/Caches/quarkOriginals');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'exclude');
    expect(calls.single.arguments, {'path': '/Library/Caches/quarkOriginals'});
  });

  test('Android asks nothing: its cache folder is never backed up', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await excludeFromBackup('/data/cache/quarkOriginals');

    expect(calls, isEmpty);
  });

  test('a platform that does not answer leaves the folder alone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          backupExclusionChannel,
          (call) async => throw PlatformException(code: 'failed'),
        );

    await expectLater(excludeFromBackup('/x'), completes);
  });
}
