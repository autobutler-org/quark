import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/file_browser_landing_config.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/auth_salt.dart';
import '../support/fake_io_http.dart';
import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// #2139: a member's grants are sparse, so the real root holds nothing but the
/// `users` and `groups` scaffolding and their own files sit two clicks down.
/// The browser opens in their home instead — but only when the URL names no
/// path of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded outside the fake clock, so setup can derive its keys.
  setUpAll(ChatCrypto.load);

  setUpAll(mockSecureStorage);

  /// What a stat answers with. A member may list `groups` but not stat it:
  /// their grant sits on the group's own folder, and stat asks for read on
  /// the path itself.
  late int statStatus;

  /// What `/api/v0/access/mine` answers. Nothing is shared by default.
  late String sharedWithMe;

  /// What a folder listing answers. Empty by default.
  late String listing;

  /// Records where every request went and answers each one, so nothing
  /// under test hangs waiting for a Quark.
  late FakeIoQuark overrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setUsername('alice');
    AppSettings.instance.isAdmin.value = false;
    statStatus = 200;
    sharedWithMe = '{"items":[]}';
    listing = '[]';
    overrides = FakeIoQuark((method, url) async {
      if (url.path.endsWith('/api/v0/files/stat')) {
        return (
          status: statStatus,
          body: jsonEncode({
            'isDir': true,
            'fileType': 'folder',
            'name': 'docs',
          }),
        );
      }
      if (url.path.endsWith('/api/v0/access/mine')) {
        return (status: 200, body: sharedWithMe);
      }
      if (url.path.endsWith('/api/v0/files')) {
        return (status: 200, body: listing);
      }
      return (status: 200, body: '[]');
    });
  });

  tearDown(() async {
    AppSettings.instance.isAdmin.value = false;
    await AppSettings.instance.setUsername(null);
  });

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  /// Every listing request, as the `rootDir` each one asked for. A request
  /// with no `rootDir` is the real root, and reads as ''.
  List<String> listedPaths(List<Uri> all) => all
      .where((u) => u.path.endsWith('/api/v0/files'))
      .map((u) => u.queryParameters['rootDir'] ?? '')
      .toList();

  Future<void> pumpBrowser(WidgetTester tester, {String? initialPath}) async {
    await tester.pumpWidget(
      MaterialApp(home: FileBrowserPage(initialPath: initialPath)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('the welcome (#2022)', () {
    const card = ValueKey('files_welcome');
    const upload = ValueKey('welcome_upload');
    const newFolder = ValueKey('welcome_new_folder');
    const vault = ValueKey('welcome_vault');

    testWidgets('a launch on a stored session is not greeted', (tester) async {
      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.byKey(card), findsNothing);
        expect(find.textContaining('Welcome'), findsNothing);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a new owner gets the start-here card until they dismiss it', (
      tester,
    ) async {
      AppSettings.instance.isAdmin.value = true;
      await AppSettings.instance.welcomeNewOwner();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.text('Welcome, alice'), findsOne);
        expect(find.byKey(upload), findsOne);
        expect(find.byKey(newFolder), findsOne);
        expect(find.byKey(vault), findsOne);

        await tester.tap(find.byKey(const ValueKey('welcome_card_dismiss')));
        await tester.pump();

        expect(find.byKey(card), findsNothing);
      }, createHttpClient: overrides.createHttpClient);

      // Dismissed for good: the next launch does not bring it back.
      await AppSettings.instance.load();
      expect(AppSettings.instance.filesWelcome.value, FilesWelcome.none);
    });

    testWidgets('finishing setup lands the owner on the card', (tester) async {
      // The real router, so the wizard's last button runs the real
      // onSetupComplete.
      setViewport(tester, const Size(1200, 2400));
      await AppSettings.instance.setUsername(null);
      await AppSettings.instance.acceptTerms();
      authStatusProbe = () async => const AuthStatus(setupComplete: false);
      authHttpClientFactory = () => AuthSaltClient(
        MockClient(
          (_) async => http.Response(jsonEncode({'token': 'owner-token'}), 200),
        ),
      );
      addTearDown(() async {
        authStatusProbe = AuthService.checkStatus;
        authHttpClientFactory = () => sharedHttpClient;
        await AppSettings.instance.setSessionToken(null);
      });

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'ada');
        await tester.enterText(fields.at(1), 'correct-horse-battery');
        await tester.enterText(fields.at(2), 'correct-horse-battery');
        await tester.tap(find.text('Create account'));
        await pumpWhileDeriving(tester);
        await tester.pumpAndSettle();

        // Mid-wizard: the account exists, but nothing is owed yet.
        expect(AppSettings.instance.filesWelcome.value, FilesWelcome.none);

        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(FileBrowserPage), findsOne);
        expect(find.text('Welcome, ada'), findsOne);
        expect(find.byKey(upload), findsOne);

        // A session exists now, so the events stream has a reconnect timer
        // going; stop it before the binding counts timers.
        EventsService.instance.stop();
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('the card fits a phone, labels and all', (tester) async {
      setViewport(tester, const Size(360, 640));
      AppSettings.instance.isAdmin.value = true;
      await AppSettings.instance.welcomeNewOwner();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.byKey(card), findsOne);
        expect(find.text('Upload'), findsOne);
        expect(find.text('New folder'), findsOne);
        expect(find.text('Open Vault'), findsOne);
        expect(tester.takeException(), isNull);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('Vault is offered to a member too (#3461)', (tester) async {
      AppSettings.instance.isAdmin.value = false;
      await AppSettings.instance.welcomeNewOwner();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.byKey(upload), findsOne);
        expect(find.byKey(vault), findsOne);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a sign-in gets one line and no actions', (tester) async {
      AppSettings.instance.greetSignIn();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.text('Welcome back, alice'), findsOne);
        expect(find.byKey(upload), findsNothing);
        expect(find.byKey(newFolder), findsNothing);
        expect(find.byKey(vault), findsNothing);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a session with no stored name is greeted without one', (
      tester,
    ) async {
      await AppSettings.instance.setUsername(null);
      AppSettings.instance.isAdmin.value = true;
      AppSettings.instance.greetSignIn();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.text('Welcome back'), findsOne);
        expect(find.textContaining('null'), findsNothing);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a folder opened by its URL is not greeted', (tester) async {
      AppSettings.instance.greetSignIn();

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester, initialPath: '/users/bob/shared');

        expect(find.byKey(card), findsNothing);
      }, createHttpClient: overrides.createHttpClient);
    });
  });

  testWidgets('a member lands in their own files', (tester) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(
        listedPaths(overrides.requested),
        contains('users/alice'),
        reason: 'a bare /files opens the signed-in member\'s home',
      );
      expect(
        listedPaths(overrides.requested),
        isNot(contains('')),
        reason: 'the real root holds scaffolding, not their files',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('an admin lands at the real root', (tester) async {
    AppSettings.instance.isAdmin.value = true;

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(listedPaths(overrides.requested), contains(''));
      expect(listedPaths(overrides.requested), isNot(contains('users/alice')));
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a deep link wins over the landing path', (tester) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/users/bob/shared');

      expect(
        listedPaths(overrides.requested),
        contains('users/bob/shared'),
        reason: 'a path in the URL is what the user asked for',
      );
      expect(
        listedPaths(overrides.requested),
        isNot(contains('users/alice')),
        reason: 'the home default must not steal a deep link or a reload',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('users and groups say what they are for (#2476)', (tester) async {
    const note = ValueKey('folder_explainer');
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/groups');
      expect(find.byKey(note), findsOne);
      expect(find.text('Group folders'), findsOne);

      await pumpBrowser(tester, initialPath: '/users');
      expect(find.text('Home folders'), findsOne);

      await pumpBrowser(tester);
      expect(find.byKey(note), findsNothing, reason: 'a home needs no note');
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a folder whose stat fails is still listed at once', (
    tester,
  ) async {
    // A member may list `groups` but not stat it, and the listing is held back
    // until the stat says what the path is. When the stat fails, the folder
    // has to be listed there and then — it used to wait for the refresh timer,
    // spinning for as long as fifteen seconds.
    statStatus = 404;

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/groups');
      // The stat answers after the first frames: the listing it gates is
      // issued once it comes back, not on the refresh timer.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        listedPaths(overrides.requested),
        contains('groups'),
        reason: 'a failed stat must not leave the folder unlisted',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('an admin flag arriving late moves the admin off their home', (
    tester,
  ) async {
    // The flag is not persisted: `/auth/status` answers after the page is
    // already built, so a reload lands an admin in their home first.
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);
      expect(listedPaths(overrides.requested), contains('users/alice'));

      AppSettings.instance.isAdmin.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        listedPaths(overrides.requested),
        contains(''),
        reason: 'the admin belongs at the root they would have landed on',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  // #3211: `isAdmin` is not saved between launches, so an admin's Files used
  // to list their home, then the root once `/auth/status` answered, and fetch
  // the recent strip twice. The first listing now waits for the answer.
  group('the landing waits for /auth/status (#3211)', () {
    late Completer<http.Response> status;

    setUp(() async {
      // An earlier page started the events socket; signing in here would
      // connect it outside the test's zone.
      EventsService.instance.stop();
      await AppSettings.instance.setSessionToken('session-token');
      authHttpClientFactory = () => MockClient((request) async {
        if (request.url.path.endsWith('/api/v0/auth/status')) {
          return status.future;
        }
        return http.Response('{}', 200);
      });
      // Signing in above built the shared client outside the test's zone.
      resetSharedHttpClient();
    });

    tearDown(() async {
      authHttpClientFactory = () => sharedHttpClient;
      // Forgets the failure a test left behind.
      AuthService.stopWatchingAccount();
      await AppSettings.instance.setSessionToken(null);
    });

    http.Response answer({required bool isAdmin}) => http.Response(
      jsonEncode({'setup': true, 'username': 'alice', 'isAdmin': isAdmin}),
      200,
    );

    /// Mounts Files while `/auth/status` is still out, then lets [settle]
    /// answer it and waits for the listing that follows.
    Future<void> mountThenSettle(
      WidgetTester tester,
      FutureOr<void> Function() settle,
    ) async {
      // Made in the test body, so it answers on the test's fake clock.
      status = Completer<http.Response>();
      unawaited(AuthService.refreshAccount());
      await pumpBrowser(tester);
      expect(
        listedPaths(overrides.requested),
        isEmpty,
        reason: 'nothing is listed before the Quark says who is signed in',
      );
      expect(
        find.byType(QuarkLoader),
        findsWidgets,
        reason: 'the wait shows a loader, not a blank page',
      );
      await settle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // A session starts the events socket; stop its reconnect timer before
      // the binding counts timers.
      EventsService.instance.stop();
    }

    testWidgets('an admin lists the root once', (tester) async {
      await HttpOverrides.runZoned(() async {
        await mountThenSettle(
          tester,
          () => status.complete(answer(isAdmin: true)),
        );

        expect(listedPaths(overrides.requested), ['']);
        expect(
          overrides.requested.where(
            (u) => u.path.endsWith('/api/v0/files/recent'),
          ),
          hasLength(1),
          reason: 'the recent strip is fetched once, for the root',
        );
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a member lists their home once', (tester) async {
      await HttpOverrides.runZoned(() async {
        await mountThenSettle(
          tester,
          () => status.complete(answer(isAdmin: false)),
        );

        expect(listedPaths(overrides.requested), ['users/alice']);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a failed status lists the home and says so', (tester) async {
      await HttpOverrides.runZoned(() async {
        await mountThenSettle(
          tester,
          () => status.complete(http.Response('', 500)),
        );

        expect(listedPaths(overrides.requested), ['users/alice']);
        expect(find.byType(SnackBar), findsOne);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a status that never answers stops holding the listing', (
      tester,
    ) async {
      await HttpOverrides.runZoned(() async {
        await mountThenSettle(
          tester,
          () => tester.pump(FileBrowserLandingConfig.accountWait),
        );

        expect(listedPaths(overrides.requested), ['users/alice']);
        expect(find.byType(SnackBar), findsOne);
        // Let the abandoned request time out before the binding counts
        // timers.
        await tester.pump(kAuthRequestTimeout);
      }, createHttpClient: overrides.createHttpClient);
    });

    testWidgets('a deep link does not wait', (tester) async {
      await HttpOverrides.runZoned(() async {
        // Made in the test body, so it answers on the test's fake clock.
        status = Completer<http.Response>();
        unawaited(AuthService.refreshAccount());
        await pumpBrowser(tester, initialPath: '/users/bob/shared');

        expect(listedPaths(overrides.requested), ['users/bob/shared']);
        status.complete(answer(isAdmin: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(listedPaths(overrides.requested), ['users/bob/shared']);
        EventsService.instance.stop();
      }, createHttpClient: overrides.createHttpClient);
    });
  });

  testWidgets('switching Quarks leaves the old one\'s folder behind', (
    tester,
  ) async {
    // #2230: the drawer switches Quarks without leaving /files, so the page
    // stays mounted and has to drop the folder it had open on the last one.
    // addHost makes the new entry active, so step back to the first one.
    await AppSettings.instance.addHost(
      HostEntry(name: 'Cabin', hostAddress: 'http://cabin.local'),
    );
    final cabin = AppSettings.instance.activeIndex;
    await AppSettings.instance.setActiveIndex(cabin - 1);

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester, initialPath: '/users/bob/shared');
      overrides.requested.clear();

      await AppSettings.instance.setActiveIndex(cabin);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final listings = overrides.requested.where(
        (u) => u.path.endsWith('/api/v0/files'),
      );
      expect(listings, isNotEmpty, reason: 'the new Quark is listed');
      expect(listings.map((u) => u.host).toSet(), {'cabin.local'});
      expect(
        listedPaths(overrides.requested),
        isNot(contains('users/bob/shared')),
        reason: 'that folder belonged to the last Quark',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('a member sees My files and Groups, an admin All files too', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(find.byKey(const ValueKey('file_shortcut_my_files')), findsOne);
      expect(find.byKey(const ValueKey('file_shortcut_groups')), findsOne);
      expect(
        find.byKey(const ValueKey('file_shortcut_all_files')),
        findsNothing,
        reason: 'only an admin can open the real root',
      );

      AppSettings.instance.isAdmin.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('file_shortcut_all_files')), findsOne);
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('Shared with me stays out of the way until something is shared', (
    tester,
  ) async {
    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(
        find.byKey(const ValueKey('file_shortcut_shared_with_me')),
        findsNothing,
        reason: 'a shortcut that opens nothing is worse than no shortcut',
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('Shared with me appears once something has been shared', (
    tester,
  ) async {
    sharedWithMe = jsonEncode({
      'items': [
        {'relPath': 'users/bob/Trip', 'level': 'read', 'owner': 'bob'},
      ],
    });

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);

      expect(
        find.byKey(const ValueKey('file_shortcut_shared_with_me')),
        findsOne,
      );
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('Shared with me lists a lone share rather than opening it', (
    tester,
  ) async {
    sharedWithMe = jsonEncode({
      'items': [
        {'relPath': 'users/bob/Trip', 'level': 'read', 'owner': 'bob'},
      ],
    });

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);
      await tester.tap(
        find.byKey(const ValueKey('file_shortcut_shared_with_me')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SharedRootsSheet), findsOne);
      expect(find.text('Shared by bob'), findsOne);
    }, createHttpClient: overrides.createHttpClient);
  });

  // #1565, #1566: the list's columns are the ones this device has chosen, and
  // the picker changes them in place and for good.
  testWidgets(
    'the list shows the chosen columns, and the picker changes them',
    (tester) async {
      listing = jsonEncode([
        {
          'name': 'budget.csv',
          'size': 2048,
          'isDir': false,
          'deviceName': 'Attic',
          'dirPath': 'users/alice/budget.csv',
          'modifiedAt': DateTime(2026, 10, 6, 14, 30).toUtc().toIso8601String(),
        },
      ]);
      Finder header(String column) =>
          find.byKey(ValueKey('file_sort_header_$column'));

      await HttpOverrides.runZoned(() async {
        await pumpBrowser(tester);

        expect(find.text('budget.csv'), findsOneWidget);
        expect(header('modified'), findsOneWidget);
        expect(header('size'), findsOneWidget);
        expect(header('type'), findsNothing);
        expect(header('device'), findsNothing);
        expect(find.text('Oct 6, 2026'), findsOneWidget);

        // The default test window is narrower than the bar's breakpoint, so
        // the picker is the Views menu's Columns section.
        await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('file_top_bar_views_column_kind')),
        );
        await tester.tap(
          find.byKey(const ValueKey('file_top_bar_views_column_size')),
        );
        await tester.pumpAndSettle();

        expect(header('type'), findsOneWidget);
        expect(find.text('Spreadsheet'), findsOneWidget);
        expect(header('size'), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList('fileListColumns'),
          unorderedEquals(['kind', 'modified']),
        );
      }, createHttpClient: overrides.createHttpClient);
    },
  );

  testWidgets('Shared with me asks which one when there are several', (
    tester,
  ) async {
    sharedWithMe = jsonEncode({
      'items': [
        {'relPath': 'users/bob/Trip', 'level': 'read', 'owner': 'bob'},
        {'relPath': 'Family', 'level': 'write', 'owner': 'carol'},
      ],
    });

    await HttpOverrides.runZoned(() async {
      await pumpBrowser(tester);
      await tester.tap(
        find.byKey(const ValueKey('file_shortcut_shared_with_me')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SharedRootsSheet), findsOne);
      expect(find.text('Shared by bob'), findsOne);
      expect(find.text('Shared by carol'), findsOne);
    }, createHttpClient: overrides.createHttpClient);
  });
}
