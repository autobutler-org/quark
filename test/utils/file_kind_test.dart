import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_kind.dart';

void main() {
  test('fileKindForName classifies by lowercase extension', () {
    expect(fileKindForName('logo.svg'), FileKind.svg);
    expect(fileKindForName('clip.ts'), FileKind.video, reason: 'MPEG-TS');
    expect(fileKindForName('app.tsx'), FileKind.code);
    expect(fileKindForName('BEACH.JPG'), FileKind.image);
    expect(fileKindForName('budget.xlsm'), FileKind.xlsx);
    expect(fileKindForName('deck.odp'), FileKind.slideshow);
    expect(fileKindForName('Deck.ODP'), FileKind.slideshow);
    expect(fileKindForName('notes.qdoc'), FileKind.qdoc);
    expect(fileKindForName('backup.tar.gz'), FileKind.archive);
    expect(fileKindForName('Makefile'), FileKind.generic);
  });

  test('only natively decoded formats preview without the server', () {
    expect(clientDecodedImageExtensions, contains(fileExtension('A.PNG')));
    for (final name in ['a.heic', 'a.raf', 'a.avif', 'a.bmp']) {
      expect(
        clientDecodedImageExtensions,
        isNot(contains(fileExtension(name))),
      );
    }
  });

  test('only prose files are spell checked', () {
    for (final name in ['notes.txt', 'README.md', 'guide.markdown', 'a.RST']) {
      expect(isProseFile(name), isTrue, reason: name);
    }
    // Text, but not prose: underlining its tokens would be noise.
    for (final name in ['server.log', '.env', 'main.go', 'app.json', 'x']) {
      expect(isProseFile(name), isFalse, reason: name);
    }
  });

  test('every archive extension the server reads is an archive (#3232)', () {
    for (final name in [
      'a.tar.zst',
      'a.tzst',
      'a.tar.xz',
      'a.txz',
      'a.tar.bz2',
      'a.tbz2',
      'a.tbz',
      'a.zst',
      'a.xz',
      'a.bz2',
      'a.cbz',
      'a.cb7',
      'a.jar',
      'a.apk',
      'a.whl',
      'A.CBZ',
    ]) {
      expect(fileKindForName(name), FileKind.archive, reason: name);
    }
  });
}
