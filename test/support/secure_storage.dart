import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Stands in for flutter_secure_storage's platform channel, which has no
/// plugin behind it in a test, until the enclosing test or group ends.
///
/// With no [store], every call answers null: nothing is ever stored. With a
/// [store], `read`, `write` and `delete` go to it, so a value written can be
/// read back; every other call answers null.
///
/// Call it from `setUp`, `setUpAll` or a test: `setUpAll(mockSecureStorage);`.
void mockSecureStorage([Map<String, String>? store]) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    if (store == null) return null;
    final key = call.arguments['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key!] = call.arguments['value'] as String;
      case 'delete':
        store.remove(key);
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
}
