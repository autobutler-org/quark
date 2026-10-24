import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

void main() {
  // ─── trimTrailingSlashes ───────────────────────────────────────────
  group('trimTrailingSlashes', () {
    for (final (input, want) in [
      ('photos/', 'photos'),
      ('photos///', 'photos'),
      ('photos', 'photos'),
      ('  photos/  ', 'photos'),
      ('', ''),
      ('   ', ''),
      ('/photos/', '/photos'),
    ]) {
      test('("$input") is "$want"', () {
        expect(trimTrailingSlashes(input), want);
      });
    }
  });

  // ─── normalizePath ─────────────────────────────────────────────────
  group('normalizePath', () {
    for (final (input, want) in [
      ('', ''),
      ('/', ''),
      ('photos', '/photos'),
      ('/photos', '/photos'),
      ('/photos/', '/photos'),
      ('/photos/vacation/', '/photos/vacation'),
      ('  /photos  ', '/photos'),
    ]) {
      test('("$input") is "$want"', () {
        expect(normalizePath(input), want);
      });
    }
  });

  // ─── joinPath ──────────────────────────────────────────────────────
  group('joinPath', () {
    for (final (base, segment, want) in [
      ('/photos', 'vacation', '/photos/vacation'),
      ('/photos', '', '/photos'),
      ('', 'photos', '/photos'),
      ('/photos', '/vacation/', '/photos/vacation'),
      ('', '', ''),
      ('/photos/', 'vacation', '/photos/vacation'),
    ]) {
      test('("$base", "$segment") is "$want"', () {
        expect(joinPath(base, segment), want);
      });
    }
  });

  // ─── parentPath ────────────────────────────────────────────────────
  group('parentPath', () {
    for (final (input, want) in [
      ('/photos/vacation', '/photos'),
      ('/photos', ''),
      ('', ''),
      ('/', ''),
      ('/a/b/c/d', '/a/b/c'),
    ]) {
      test('("$input") is "$want"', () {
        expect(parentPath(input), want);
      });
    }
  });

  // ─── toRootDir ─────────────────────────────────────────────────────
  group('toRootDir', () {
    for (final (input, want) in [
      ('/photos', 'photos'),
      ('', ''),
      ('/', ''),
      ('/photos/vacation', 'photos/vacation'),
    ]) {
      test('("$input") is "$want"', () {
        expect(toRootDir(input), want);
      });
    }
  });

  // ─── serialOrNull ──────────────────────────────────────────────────
  group('serialOrNull', () {
    for (final (input, want) in <(String, String?)>[
      ('ABC123', 'ABC123'),
      ('', null),
      ('   ', null),
      ('  ABC123  ', 'ABC123'),
    ]) {
      test('("$input") is ${want == null ? 'null' : '"$want"'}', () {
        expect(serialOrNull(input), want);
      });
    }
  });

  // ─── isHomeRoot ────────────────────────────────────────────────────
  // The same cases as the Quark's TestIsHomeRoot, so the two stay in step.
  group('isHomeRoot', () {
    for (final (serial, path, want) in [
      ('', 'users/bob', true),
      ('', '/users/bob/', true),
      ('', 'users/./bob', true),
      ('', 'users', false),
      ('', 'users/bob/notes.txt', false),
      ('', 'users/bob/sub', false),
      ('', 'bob', false),
      ('', 'shared/users/bob', false),
      ('USB1', 'users/bob', false),
    ]) {
      test('($serial, $path) is $want', () {
        expect(isHomeRoot(serial, path), want);
      });
    }
  });

  // ─── isUsersDir ────────────────────────────────────────────────────
  group('isUsersDir', () {
    for (final (serial, path, want) in [
      ('', 'users', true),
      ('', '/users/', true),
      ('', './users', true),
      ('', 'users/bob', false),
      ('', 'shared/users', false),
      ('', 'users.txt', false),
      ('USB1', 'users', false),
    ]) {
      test('($serial, $path) is $want', () {
        expect(isUsersDir(serial, path), want);
      });
    }
  });

  // ─── isGroupRoot ───────────────────────────────────────────────────
  // The same cases as the Quark's TestIsGroupRoot, so the two stay in step.
  group('isGroupRoot', () {
    for (final (serial, path, want) in [
      ('', 'groups/Family', true),
      ('', '/groups/Family/', true),
      ('', 'groups/./Family', true),
      ('', 'groups', false),
      ('', 'groups/Family/notes.txt', false),
      ('', 'groups/Family/sub', false),
      ('', 'Family', false),
      ('', 'shared/groups/Family', false),
      ('', 'users/Family', false),
      ('USB1', 'groups/Family', false),
    ]) {
      test('($serial, $path) is $want', () {
        expect(isGroupRoot(serial, path), want);
      });
    }
  });

  // ─── isGroupsDir ───────────────────────────────────────────────────
  group('isGroupsDir', () {
    for (final (serial, path, want) in [
      ('', 'groups', true),
      ('', '/groups/', true),
      ('', './groups', true),
      ('', 'groups/Family', false),
      ('', 'shared/groups', false),
      ('', 'groups.txt', false),
      ('', 'users', false),
      ('USB1', 'groups', false),
    ]) {
      test('($serial, $path) is $want', () {
        expect(isGroupsDir(serial, path), want);
      });
    }
  });

  // ─── homePath / landingPath ────────────────────────────────────────
  group('homePath', () {
    for (final (username, want) in [
      ('alice', '/users/alice'),
      ('  bob  ', '/users/bob'),
      ('', ''),
      (null, ''),
    ]) {
      test('($username) is "$want"', () {
        expect(homePath(username), want);
      });
    }
  });

  group('landingPath', () {
    test('a member starts in their own files', () {
      expect(landingPath(isAdmin: false, username: 'alice'), '/users/alice');
    });

    test('an admin starts at the real root', () {
      expect(landingPath(isAdmin: true, username: 'root'), '');
    });

    test('an account with no recorded username starts at the real root', () {
      expect(landingPath(isAdmin: false, username: null), '');
    });
  });

  // ─── isWithin ──────────────────────────────────────────────────────
  group('isWithin', () {
    for (final (root, path, want) in [
      ('', '/anything', true),
      ('', '', true),
      ('/users/alice', '/users/alice', true),
      ('/users/alice', '/users/alice/docs', true),
      ('/users/alice', '/users', false),
      ('/users/alice', '', false),
      ('/users/alice', '/users/alicia', false),
      ('users/alice', '/users/alice/docs', true),
    ]) {
      test('($root, $path) is $want', () {
        expect(isWithin(root, path), want);
      });
    }
  });
}
