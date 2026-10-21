import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/quicktype_identities.dart';
import 'package:quark/services/quicktype_identities_io.dart' as io;
import 'package:quark/services/quicktype_identities_stub.dart' as stub;

/// #3599: the `org.autobutler/quicktype` channel as the Dart side speaks it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(QuickTypeIdentities.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  const github = (
    domain: 'github.com',
    username: 'grace',
    record: 'acct_0123456789abcdef0123456789abcdef/7',
  );

  setUp(() {
    calls = [];
    io.isIOS = () => true;
  });

  tearDown(() {
    io.isIOS = () => false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('hands iOS the domain, username and record of each identity', () async {
    answer((_) => true);
    expect(await io.replace([github]), isTrue);
    expect(calls.single.method, 'replace');
    expect(calls.single.arguments, {
      'identities': [
        {
          'domain': 'github.com',
          'username': 'grace',
          'record': 'acct_0123456789abcdef0123456789abcdef/7',
        },
      ],
    });
  });

  test('says when iOS stored nothing', () async {
    answer((_) => false);
    expect(await io.replace([github]), isFalse);
  });

  test('a refused replace or clear throws', () async {
    answer((_) => throw PlatformException(code: 'failed'));
    await expectLater(io.replace([github]), throwsA(isA<PlatformException>()));
    await expectLater(io.clear(), throwsA(isA<PlatformException>()));
  });

  test('clears the store', () async {
    answer((_) => null);
    await io.clear();
    expect(calls.single.method, 'clear');
  });

  test('off iOS there is no store and nothing is asked', () async {
    io.isIOS = () => false;
    answer((_) => true);
    expect(io.isSupported(), isFalse);
    expect(await io.replace([github]), isFalse);
    await io.clear();
    expect(calls, isEmpty);
  });

  test('the web stores nothing', () async {
    expect(stub.isSupported(), isFalse);
    expect(await stub.replace([github]), isFalse);
    await stub.clear();
  });
}
