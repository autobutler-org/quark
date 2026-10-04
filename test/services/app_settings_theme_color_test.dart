import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #2740: the theme color is the user's own when they picked one, otherwise the
/// Quark's, and what it resolved to is remembered per host so the sign-in
/// page wears it.
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

  const twoHosts = [
    {'name': 'One', 'hostAddress': 'http://one.local'},
    {'name': 'Two', 'hostAddress': 'http://two.local'},
  ];

  /// Boots [AppSettings] on [twoHosts] with [themeColors] cached, host one active.
  Future<void> loadWith([Map<String, String>? themeColors]) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode(twoHosts),
      'activeHostIndex': 0,
      'themeColors': ?(themeColors == null ? null : jsonEncode(themeColors)),
    });
    await settings.load();
  }

  Future<Map<String, dynamic>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('themeColors') ?? '{}')
        as Map<String, dynamic>;
  }

  group('resolution', () {
    test('nothing known is classic', () async {
      await loadWith();

      expect(settings.themeColor.value, QuarkThemeColor.classic);
      expect(settings.quarkThemeColor.value, isNull);
      expect(settings.userThemeColor.value, isNull);
    });

    test("a signed-out user gets the Quark's default", () async {
      await loadWith();

      await settings.setQuarkThemeColor('lime');

      expect(settings.themeColor.value, QuarkThemeColor.lime);
    });

    test("the user's own theme color wins over the Quark's", () async {
      await loadWith();

      await settings.setQuarkThemeColor('lime');
      await settings.setUserThemeColor('#aabbcc');

      expect(settings.themeColor.value.storageValue, '#aabbcc');
    });

    test("an empty override follows the Quark's, live", () async {
      await loadWith();
      await settings.setQuarkThemeColor('lime');
      await settings.setUserThemeColor('violet');

      await settings.setUserThemeColor('');
      expect(settings.themeColor.value, QuarkThemeColor.lime);

      await settings.setQuarkThemeColor('pink');
      expect(settings.themeColor.value, QuarkThemeColor.pink);

      await settings.setQuarkThemeColor('');
      expect(settings.themeColor.value, QuarkThemeColor.classic);
    });

    test('an unknown name falls back to classic', () async {
      await loadWith();

      await settings.setQuarkThemeColor('chartreuse');

      expect(settings.themeColor.value, QuarkThemeColor.classic);
    });
  });

  group('the per-host cache', () {
    test('is loaded at startup, before anything is fetched', () async {
      await loadWith({'http://one.local': 'violet'});

      expect(settings.themeColor.value, QuarkThemeColor.violet);
    });

    test('records what the theme color resolved to', () async {
      await loadWith();

      await settings.setQuarkThemeColor('lime');
      expect(await cached(), {'http://one.local': 'lime'});

      await settings.setUserThemeColor('violet');
      expect(await cached(), {'http://one.local': 'violet'});

      // Back on the default theme color there is nothing worth remembering.
      await settings.setUserThemeColor('');
      await settings.setQuarkThemeColor('');
      expect(await cached(), isEmpty);
    });

    test("stands until the user's own theme color is known", () async {
      await loadWith({'http://one.local': 'violet'});

      // The Quark's default arrives first, at the sign-in page: no change,
      // or the color would move again after signing in.
      await settings.setQuarkThemeColor('lime');
      expect(settings.themeColor.value, QuarkThemeColor.violet);

      await settings.setUserThemeColor('');
      expect(settings.themeColor.value, QuarkThemeColor.lime);
    });

    test('survives signing out', () async {
      await loadWith();
      await settings.setQuarkThemeColor('lime');
      await settings.setUserThemeColor('violet');

      await settings.setUserThemeColor(null);

      expect(settings.themeColor.value, QuarkThemeColor.violet);
      expect(await cached(), {'http://one.local': 'violet'});
    });

    test('switching hosts switches color at once', () async {
      await loadWith({
        'http://one.local': 'violet',
        'http://two.local': 'pink',
      });
      await settings.setQuarkThemeColor('lime');
      await settings.setUserThemeColor('violet');

      await settings.setActiveIndex(1);

      expect(settings.themeColor.value, QuarkThemeColor.pink);
      // Host one's theme colors do not follow the user to host two.
      expect(settings.quarkThemeColor.value, isNull);
      expect(settings.userThemeColor.value, isNull);

      await settings.setActiveIndex(0);
      expect(settings.themeColor.value, QuarkThemeColor.violet);
    });

    test('a host never seen shows the default until it answers', () async {
      await loadWith({'http://one.local': 'violet'});

      await settings.setActiveIndex(1);
      expect(settings.themeColor.value, QuarkThemeColor.classic);

      await settings.setQuarkThemeColor('lime');
      expect(settings.themeColor.value, QuarkThemeColor.lime);
      expect(await cached(), {
        'http://one.local': 'violet',
        'http://two.local': 'lime',
      });
    });

    test('removing a host forgets its theme color', () async {
      await loadWith({
        'http://one.local': 'violet',
        'http://two.local': 'pink',
      });

      await settings.removeHost(0);

      expect(await cached(), {'http://two.local': 'pink'});
      expect(settings.activeHost, 'http://two.local');
      expect(settings.themeColor.value, QuarkThemeColor.pink);
    });
  });
}
