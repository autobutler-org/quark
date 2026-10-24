import 'package:flutter_test/flutter_test.dart';
import 'package:quark/router.dart';

/// Which page of its own opens each kind of file: the one table Files and
/// `/view` both read.
void main() {
  test('each kind with a page of its own maps to that page', () {
    const table = {
      'src/main.go': '/code/src/main.go',
      'notes/todo.txt': '/code/notes/todo.txt',
      'build/Makefile': '/code/build/Makefile',
      'docs/readme.md': '/markdown/docs/readme.md',
      'parts/gear.stl': '/model/parts/gear.stl',
      'a/plan.qdoc': '/docs/a/plan.qdoc',
      'a/budget.qsheet': '/sheets/a/budget.qsheet',
      'a/talk.qslide': '/slides/a/talk.qslide',
    };
    for (final MapEntry(key: path, value: route) in table.entries) {
      expect(viewerRouteFor(path), route, reason: path);
    }
  });

  test('a kind FileViewerPage shows has no page of its own', () {
    for (final path in [
      'a/photo.jpg',
      'a/clip.mp4',
      'a/paper.pdf',
      'a/x.zip',
    ]) {
      expect(viewerRouteFor(path), isNull, reason: path);
    }
  });

  test('the serial rides along, and from reaches only a presentation', () {
    expect(
      viewerRouteFor('a/main.go', serial: 's1'),
      '/code/a/main.go?serial=s1',
    );
    expect(
      viewerRouteFor('a/talk.qslide', from: '/files/a'),
      '/slides/a/talk.qslide?from=/files/a',
    );
    expect(
      viewerRouteFor('a/plan.qdoc', from: '/files/a'),
      '/docs/a/plan.qdoc',
    );
  });

  test('a folder whose name has a dot is classified by the file name', () {
    expect(viewerRouteFor('v1.2/main.go'), '/code/v1.2/main.go');
  });
}
