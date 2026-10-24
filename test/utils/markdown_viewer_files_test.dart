import 'package:flutter_test/flutter_test.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/markdown_viewer_files.dart';

/// Which files the Markdown viewer takes (#2987), where the router sends
/// them, and what a link or image address inside one points at.
void main() {
  test('Markdown opens in the viewer; other prose and source do not', () {
    expect(opensInMarkdownViewer('README.md'), isTrue);
    expect(opensInMarkdownViewer('notes/Guide.MARKDOWN'), isTrue);
    expect(opensInMarkdownViewer('todo.txt'), isFalse);
    expect(opensInMarkdownViewer('main.go'), isFalse);
    expect(opensInMarkdownViewer('md'), isFalse);
  });

  test('a /view link to Markdown opens its viewer, .txt the code viewer', () {
    expect(
      viewFileRedirect('notes/readme.md', null),
      '/markdown/notes/readme.md',
    );
    expect(
      viewFileRedirect('notes/readme.markdown', 's1'),
      '/markdown/notes/readme.markdown?serial=s1',
    );
    expect(viewFileRedirect('notes/todo.txt', null), '/code/notes/todo.txt');
  });

  group('resolveMarkdownLink', () {
    ({MarkdownLinkKind kind, String value}) at(String href) =>
        resolveMarkdownLink('docs/guide/readme.md', href);

    test('a relative address resolves against the file\'s folder', () {
      expect(at('img/a.png'), (
        kind: MarkdownLinkKind.file,
        value: 'docs/guide/img/a.png',
      ));
      expect(at('./other.md#section'), (
        kind: MarkdownLinkKind.file,
        value: 'docs/guide/other.md',
      ));
      expect(at('../shared/b%20c.png?raw=1'), (
        kind: MarkdownLinkKind.file,
        value: 'docs/shared/b c.png',
      ));
    });

    test('a leading slash means the files root, and .. stops there', () {
      expect(at('/top.png'), (kind: MarkdownLinkKind.file, value: 'top.png'));
      expect(at('../../../../etc/passwd'), (
        kind: MarkdownLinkKind.file,
        value: 'etc/passwd',
      ));
    });

    test('a folder name with a space or a percent survives', () {
      expect(resolveMarkdownLink('my notes/100%/a.md', 'b.png'), (
        kind: MarkdownLinkKind.file,
        value: 'my notes/100%/b.png',
      ));
    });

    test('http and https are remote', () {
      expect(at('https://example.com/a.png'), (
        kind: MarkdownLinkKind.remote,
        value: 'https://example.com/a.png',
      ));
      expect(at('HTTP://example.com').kind, MarkdownLinkKind.remote);
    });

    test('anchors, other schemes and junk are left alone', () {
      for (final href in [
        '#heading',
        '',
        'javascript:alert(1)',
        'data:image/png;base64,AAAA',
        'file:///etc/passwd',
        'mailto:a@example.com',
        '//example.com/a.png',
        'https:///nohost',
        'http://[bad',
      ]) {
        expect(at(href).kind, MarkdownLinkKind.other, reason: href);
      }
    });
  });
}
