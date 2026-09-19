import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:quark/pages/settings_page.dart';
import 'package:quark/services/app_settings.dart';

import '../support/unreachable_quark.dart';

/// #1606: a bug report needs the client build, not just the Quark's. Settings
/// showed only the server's installed version, so the app's own version came
/// from the bundle the release build stamped and had nowhere to appear.
void main() {
  final settings = AppSettings.instance;

  Future<void> clearHosts() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  }

  late HttpOverrides? priorOverrides;

  setUp(() async {
    // Settings loads six sections from the Quark on mount. None of them are
    // under test here, and an unreachable Quark fails them all promptly.
    priorOverrides = HttpOverrides.current;
    HttpOverrides.global = UnreachableQuarkHttpOverrides();
    await clearHosts();
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await clearHosts();
  });

  /// Settings never settles — its SBOM section keeps a spinner turning — so
  /// pump far enough for the bundle read and every Quark-bound load to finish.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Settings overflows its own app bar by 28px at any viewport — the brand
    // button against a fixed `leadingWidth` — with or without this change.
    // Ignore that one, keep failing on anything else. Installed here rather
    // than in setUp: testWidgets replaces the handler when the body starts.
    final priorOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = priorOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      priorOnError?.call(details);
    };

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // Order matters: PackageInfo caches the first answer in a static with no
  // reset hook, so the no-bundle case has to run before anything seeds it.
  testWidgets('stays silent when no bundle answers', (tester) async {
    // What a unit test or a shell that was never packaged looks like: the
    // plugin throws. A version the user cannot act on is worse than no row.
    await pumpSettings(tester);

    expect(find.textContaining('App version'), findsNothing);
  });

  testWidgets('shows the version stamped into the bundle', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Quark',
      packageName: 'org.autobutler.quark',
      version: '0.31.1',
      buildNumber: '42',
      buildSignature: '',
    );

    await pumpSettings(tester);

    expect(find.text('App version: 0.31.1 (42)'), findsOneWidget);
  });

  // Nothing stamps a version unless the build passed --build-name, so the
  // empty cases are the ones a developer actually sees.
  group('appVersionLabel', () {
    test('names the commit a dev run was built from', () {
      // What `make watch/frontend` produces: no tag, but a --dart-define'd sha.
      expect(
        appVersionLabel(version: '', buildNumber: '', sha: 'a1b2c3d'),
        'App version: Development build (a1b2c3d)',
      );
    });

    test('names the build kind when nothing was stamped', () {
      // A bare `flutter run`, outside the Makefile: no tag and no sha either.
      expect(
        appVersionLabel(version: '', buildNumber: '', sha: ''),
        'App version: Development build — no version stamped',
      );
      // Web omits the version.json keys rather than defaulting them, so a
      // build number can survive a missing version.
      expect(
        appVersionLabel(version: '', buildNumber: '42', sha: ''),
        'App version: Development build — no version stamped',
      );
    });

    test('drops the parenthetical when only the version was stamped', () {
      // Every target but the iOS release: nothing passes --build-number, and
      // "App version 0.31.1 ()" is what the first cut rendered.
      expect(
        appVersionLabel(version: '0.31.1', buildNumber: '', sha: 'a1b2c3d'),
        'App version: 0.31.1',
      );
    });

    test('names both when the iOS release stamped both', () {
      expect(
        appVersionLabel(version: '0.31.1', buildNumber: '42', sha: 'a1b2c3d'),
        'App version: 0.31.1 (42)',
      );
    });
  });

  // #1756: a tagged build has release notes on GitHub; a dev build has no tag
  // and so no page to send the reader to.
  group('releaseNotesUrl', () {
    test('points a tagged build at its release', () {
      // The app strips the `v` out of --build-name, the Quark keeps it.
      expect(
        releaseNotesUrl('0.31.1'),
        'https://github.com/autobutler-org/quark/releases/tag/v0.31.1',
      );
      expect(
        releaseNotesUrl('v0.31.1'),
        'https://github.com/autobutler-org/quark/releases/tag/v0.31.1',
      );
    });

    test('has nowhere to send a dev build', () {
      expect(releaseNotesUrl(''), isNull);
      expect(releaseNotesUrl('   '), isNull);
      // What an untagged Quark answers with.
      expect(releaseNotesUrl('NOSEMVER'), isNull);
    });
  });

  testWidgets('links the app version at its release notes', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Quark',
      packageName: 'org.autobutler.quark',
      version: '0.31.1',
      buildNumber: '42',
      buildSignature: '',
    );

    await pumpSettings(tester);

    final link = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('App version: 0.31.1 (42)'),
        matching: find.byType(InkWell),
      ),
    );
    expect(link.onTap, isNotNull);
  });

  // The Quark's version renders through the same label as the app's, so the
  // two cannot describe one situation two ways. It used to read "dev
  // (untagged)" where the app read "Development build".
  group('the Quark version, sharing the label', () {
    test('reads like the app when neither was built from a tag', () {
      expect(
        buildVersionLabel(version: '', sha: 'a1b2c3d'),
        'Development build (a1b2c3d)',
      );
      expect(
        appVersionLabel(version: '', buildNumber: '', sha: 'a1b2c3d'),
        'App version: Development build (a1b2c3d)',
      );
    });

    // #2035: the Quark's line lives under "Quark version (installed)" and the
    // app's names itself inline, so two "Development build (…)" lines from
    // two different commits cannot be mistaken for the page contradicting
    // itself.
    test('carries no "App version" prefix, having its own heading', () {
      expect(buildVersionLabel(version: '0.31.1'), '0.31.1');
    });

    test('shortens the commit the Quark reports in full', () {
      expect(shortGitSha('a1b2c3d4e5f6a7b8'), 'a1b2c3d');
      // Seven characters is also what the Makefile stamps into a dev run.
      expect(shortGitSha('a1b2c3d'), 'a1b2c3d');
    });

    test('treats the Quark sentinels as no commit at all', () {
      expect(shortGitSha('NOCOMMIT'), '');
      expect(shortGitSha(''), '');
      // NOCOMMIT with no tag either: nothing identifies the build.
      expect(
        buildVersionLabel(version: '', sha: shortGitSha('NOCOMMIT')),
        'Development build — no version stamped',
      );
    });
  });
}
