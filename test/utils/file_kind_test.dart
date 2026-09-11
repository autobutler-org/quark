import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_kind.dart';

void main() {
  test('fileKindForName classifies by lowercase extension', () {
    expect(fileKindForName('logo.svg'), FileKind.svg);
    expect(fileKindForName('clip.ts'), FileKind.video, reason: 'MPEG-TS');
    expect(fileKindForName('app.tsx'), FileKind.code);
    expect(fileKindForName('BEACH.JPG'), FileKind.image);
    expect(fileKindForName('budget.xlsm'), FileKind.xlsx);
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
}
