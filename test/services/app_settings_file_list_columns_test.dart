import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1565, #1566: which columns the Files list shows is a choice made on this
/// device, so it has to survive a restart and start at Modified and Size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  final settings = AppSettings.instance;

  Future<void> loadWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await settings.load();
  }

  test('defaults to Modified and Size until changed', () async {
    await loadWith({});

    expect(settings.fileListColumns.value, {
      FileListColumn.modified,
      FileListColumn.size,
    });
  });

  test('reads a persisted choice on load', () async {
    await loadWith({
      'fileListColumns': <String>['kind', 'device'],
    });

    expect(settings.fileListColumns.value, {
      FileListColumn.kind,
      FileListColumn.device,
    });
  });

  test('keeps a choice of no optional columns at all', () async {
    await loadWith({'fileListColumns': <String>[]});

    expect(settings.fileListColumns.value, isEmpty);
  });

  test('an unrecognized persisted value falls back to the default', () async {
    await loadWith({
      'fileListColumns': <String>['kind', 'garbage'],
    });

    expect(settings.fileListColumns.value, AppSettings.defaultFileListColumns);
  });

  test('setFileListColumnVisible publishes and persists the choice', () async {
    await loadWith({});

    await settings.setFileListColumnVisible(FileListColumn.kind, true);
    await settings.setFileListColumnVisible(FileListColumn.size, false);

    expect(settings.fileListColumns.value, {
      FileListColumn.kind,
      FileListColumn.modified,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('fileListColumns'),
      unorderedEquals(['kind', 'modified']),
    );

    await settings.load();
    expect(settings.fileListColumns.value, {
      FileListColumn.kind,
      FileListColumn.modified,
    });
  });
}
