import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

void main() {
  // ─── trimTrailingSlashes ───────────────────────────────────────────
  group('trimTrailingSlashes', () {
    test('removes single trailing slash', () {
      expect(trimTrailingSlashes('photos/'), 'photos');
    });

    test('removes multiple trailing slashes', () {
      expect(trimTrailingSlashes('photos///'), 'photos');
    });

    test('no-op when no trailing slash', () {
      expect(trimTrailingSlashes('photos'), 'photos');
    });

    test('trims whitespace', () {
      expect(trimTrailingSlashes('  photos/  '), 'photos');
    });

    test('returns empty for empty input', () {
      expect(trimTrailingSlashes(''), '');
    });

    test('returns empty for whitespace-only input', () {
      expect(trimTrailingSlashes('   '), '');
    });

    test('preserves leading slash', () {
      expect(trimTrailingSlashes('/photos/'), '/photos');
    });
  });

  // ─── normalizePath ─────────────────────────────────────────────────
  group('normalizePath', () {
    test('returns empty for empty string', () {
      expect(normalizePath(''), '');
    });

    test('returns empty for root slash', () {
      expect(normalizePath('/'), '');
    });

    test('adds leading slash when missing', () {
      expect(normalizePath('photos'), '/photos');
    });

    test('keeps existing leading slash', () {
      expect(normalizePath('/photos'), '/photos');
    });

    test('removes trailing slash', () {
      expect(normalizePath('/photos/'), '/photos');
    });

    test('handles nested path', () {
      expect(normalizePath('/photos/vacation/'), '/photos/vacation');
    });

    test('trims whitespace', () {
      expect(normalizePath('  /photos  '), '/photos');
    });
  });

  // ─── joinPath ──────────────────────────────────────────────────────
  group('joinPath', () {
    test('joins base and segment', () {
      expect(joinPath('/photos', 'vacation'), '/photos/vacation');
    });

    test('handles empty segment', () {
      expect(joinPath('/photos', ''), '/photos');
    });

    test('handles empty base', () {
      expect(joinPath('', 'photos'), '/photos');
    });

    test('cleans slashes on segment', () {
      expect(joinPath('/photos', '/vacation/'), '/photos/vacation');
    });

    test('handles both empty', () {
      expect(joinPath('', ''), '');
    });

    test('handles base with trailing slash', () {
      expect(joinPath('/photos/', 'vacation'), '/photos/vacation');
    });
  });

  // ─── parentPath ────────────────────────────────────────────────────
  group('parentPath', () {
    test('returns parent of nested path', () {
      expect(parentPath('/photos/vacation'), '/photos');
    });

    test('returns empty for top-level path', () {
      expect(parentPath('/photos'), '');
    });

    test('returns empty for empty input', () {
      expect(parentPath(''), '');
    });

    test('returns empty for root', () {
      expect(parentPath('/'), '');
    });

    test('handles deeply nested path', () {
      expect(parentPath('/a/b/c/d'), '/a/b/c');
    });
  });

  // ─── toRootDir ─────────────────────────────────────────────────────
  group('toRootDir', () {
    test('strips leading slash', () {
      expect(toRootDir('/photos'), 'photos');
    });

    test('returns empty for empty input', () {
      expect(toRootDir(''), '');
    });

    test('returns empty for root', () {
      expect(toRootDir('/'), '');
    });

    test('handles nested path', () {
      expect(toRootDir('/photos/vacation'), 'photos/vacation');
    });
  });

  // ─── serialOrNull ──────────────────────────────────────────────────
  group('serialOrNull', () {
    test('returns serial when non-empty', () {
      expect(serialOrNull('ABC123'), 'ABC123');
    });

    test('returns null for empty string', () {
      expect(serialOrNull(''), isNull);
    });

    test('returns null for whitespace-only', () {
      expect(serialOrNull('   '), isNull);
    });

    test('trims whitespace from valid serial', () {
      expect(serialOrNull('  ABC123  '), 'ABC123');
    });
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
}
