import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/file_event_scope.dart';

/// #2763: the Files page refreshed on every listing event anywhere on the
/// Quark. These pin which events reach the folder on screen.
void main() {
  FileEvent event(String kind, String path, {String? newPath}) =>
      FileEvent(kind: kind, path: path, newPath: newPath);

  const open = '/groups/family';

  group('a change inside the open folder', () {
    for (final kind in ['upload', 'delete', 'move', 'new_folder']) {
      test('$kind of a direct child', () {
        expect(
          eventAffectsFolder(event(kind, 'groups/family/a.txt'), open),
          isTrue,
        );
      });
    }

    test('an upload names the folder it went into', () {
      // uploadutil publishes the upload's RootDir, not the file.
      expect(
        eventAffectsFolder(event('upload', 'groups/family'), open),
        isTrue,
      );
    });

    test('a change deeper down, which may add a child folder', () {
      // A folder upload creates its parents on the way, so a file three
      // levels down can be a new child here.
      expect(
        eventAffectsFolder(event('upload', 'groups/family/trip/day1'), open),
        isTrue,
      );
    });

    test('access to a child changed', () {
      expect(
        eventAffectsFolder(event('access_changed', 'groups/family/a'), open),
        isTrue,
      );
    });

    test('something moved in from elsewhere', () {
      expect(
        eventAffectsFolder(
          event('move', 'users/ada/a.txt', newPath: 'groups/family/a.txt'),
          open,
        ),
        isTrue,
      );
    });

    test('something moved out to elsewhere', () {
      expect(
        eventAffectsFolder(
          event('move', 'groups/family/a.txt', newPath: 'users/ada/a.txt'),
          open,
        ),
        isTrue,
      );
    });
  });

  group('a change to the open folder or above it', () {
    test('the folder itself was deleted', () {
      expect(
        eventAffectsFolder(event('delete', 'groups/family'), open),
        isTrue,
      );
    });

    test('the folder itself was moved', () {
      expect(
        eventAffectsFolder(
          event('move', 'groups/family', newPath: 'groups/kin'),
          open,
        ),
        isTrue,
      );
    });

    test('an ancestor was deleted', () {
      expect(eventAffectsFolder(event('delete', 'groups'), open), isTrue);
    });

    test('access on an ancestor changed, which this folder inherits', () {
      expect(
        eventAffectsFolder(event('access_changed', 'groups'), open),
        isTrue,
      );
    });
  });

  group('a change elsewhere', () {
    test('an upload into a sibling folder', () {
      expect(
        eventAffectsFolder(event('upload', 'groups/everyone'), open),
        isFalse,
      );
    });

    test('a folder whose name starts the same', () {
      expect(
        eventAffectsFolder(event('upload', 'groups/family-old/a'), open),
        isFalse,
      );
    });

    test('a move between two other folders', () {
      expect(
        eventAffectsFolder(
          event('move', 'users/ada/a', newPath: 'users/bob/a'),
          open,
        ),
        isFalse,
      );
    });

    test('a delete in another account\'s home', () {
      expect(
        eventAffectsFolder(event('delete', 'users/bob/a.txt'), open),
        isFalse,
      );
    });
  });

  group('events that cannot be placed', () {
    test('a resync, after the Quark dropped events', () {
      expect(eventAffectsFolder(event('resync', ''), open), isTrue);
    });

    test('an access change with no path, such as a group change', () {
      expect(eventAffectsFolder(event('access_changed', ''), open), isTrue);
    });

    test('a listing event with no path', () {
      expect(eventAffectsFolder(event('upload', ''), open), isTrue);
    });
  });

  group('events that change no listing', () {
    for (final kind in [
      'job_progress',
      'trash_changed',
      'chat_message_created',
      'calendar_changed',
      'account_changed',
      'something_new',
    ]) {
      test(kind, () {
        expect(
          eventAffectsFolder(event(kind, 'groups/family/a'), open),
          isFalse,
        );
      });
    }
  });

  group('path spellings', () {
    test('leading and trailing slashes on either side', () {
      expect(
        eventAffectsFolder(
          event('delete', '/groups/family/a/'),
          'groups/family/',
        ),
        isTrue,
      );
    });

    test('the top folder sees every change', () {
      expect(eventAffectsFolder(event('upload', 'users/bob'), ''), isTrue);
      expect(eventAffectsFolder(event('upload', 'users/bob'), '/'), isTrue);
    });
  });
}
