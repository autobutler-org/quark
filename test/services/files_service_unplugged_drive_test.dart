import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/code_viewer_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// A file on a drive that was unplugged after its link was made (#3981): every
/// read a viewer makes reports it as a [DriveNotConnected], which the viewer
/// says in plain words, rather than a bare 404.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  final reads = <String, Future<Object?> Function()>{
    'downloadFileBytes': () =>
        FilesService.downloadFileBytes('books/novel.pdf', serial: 'usb1'),
    'downloadOriginalBytes': () =>
        FilesService.downloadOriginalBytes('books/novel.pdf', serial: 'usb1'),
    'statFile': () => FilesService.statFile('books/novel.pdf', serial: 'usb1'),
    'readRange': () => CodeViewerService.readRange(
      'books/notes.txt',
      start: 0,
      length: 16,
      serial: 'usb1',
    ),
  };

  for (final MapEntry(key: name, value: read) in reads.entries) {
    test('$name says the drive is not connected', () async {
      answer(404, {'error': 'storage device not found'});

      final error = await read().then<Object?>((_) => null, onError: (e) => e);

      expect(error, isA<DriveNotConnected>());
      expect(Errors.message(error, 'open the file'), Errors.driveNotConnected);
    });
  }

  test('a file that is gone from an attached drive is still a 404', () async {
    answer(404, {'error': 'file not found'});

    final error = await FilesService.downloadFileBytes(
      'books/novel.pdf',
      serial: 'usb1',
    ).then<Object?>((_) => null, onError: (e) => e);

    expect(error, isNot(isA<DriveNotConnected>()));
    expect(Errors.message(error, 'open the file'), contains('no longer there'));
  });
}
