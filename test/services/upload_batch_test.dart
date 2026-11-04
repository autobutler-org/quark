import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/upload_batch.dart';
import 'package:quark/utils/error_text.dart';

/// A batch the Quark refused partway is resent without the files that landed
/// (#3533): resending them with keepBoth used to save each again as a `_(1)`
/// copy.
void main() {
  UploadBatchFile file(String name) =>
      () async => [http.MultipartFile.fromString('files', 'x', filename: name)];

  List<UploadBatchFile> files(List<String> names) => [
    for (final name in names) file(name),
  ];

  /// Answers each request with the next of [answers]: a list of landed paths
  /// to succeed with, or an exception to throw. Records the names each
  /// request carried.
  ({
    List<List<String>> requests,
    Future<List<String>> Function(List<http.MultipartFile>) send,
  })
  quark(List<Object> answers) {
    final requests = <List<String>>[];
    var next = 0;
    return (
      requests: requests,
      send: (parts) async {
        requests.add([for (final p in parts) p.filename!]);
        final answer = answers[next++];
        if (answer is Exception) throw answer;
        return answer as List<String>;
      },
    );
  }

  group('sendUploadBatch', () {
    test(
      'a retry after a cut-off body sends only the unlanded files',
      () async {
        final q = quark([
          const UploadBatchFailure(400, ['a.jpg', 'b.jpg']),
          ['c.jpg'],
        ]);

        final landed = await sendUploadBatch(
          files: files(['a.jpg', 'b.jpg', 'c.jpg']),
          send: q.send,
        );

        expect(q.requests, [
          ['a.jpg', 'b.jpg', 'c.jpg'],
          ['c.jpg'],
        ]);
        expect(landed, ['a.jpg', 'b.jpg', 'c.jpg']);
      },
    );

    test('a file that landed under a keepBoth name is still skipped', () async {
      final q = quark([
        const UploadBatchFailure(500, ['IMG_1_(1).jpg']),
        ['IMG_2.jpg'],
      ]);

      final landed = await sendUploadBatch(
        files: files(['IMG_1.jpg', 'IMG_2.jpg']),
        send: q.send,
      );

      expect(q.requests.last, ['IMG_2.jpg']);
      expect(landed, ['IMG_1_(1).jpg', 'IMG_2.jpg']);
    });

    test('a conflict is the caller\'s to answer, with what landed', () async {
      final q = quark([
        const UploadBatchFailure(409, ['notes/a.txt']),
      ]);

      final failure =
          await sendUploadBatch(
            files: files(['a.txt', 'b.txt', 'c.txt']),
            send: q.send,
          ).then<UploadBatchFailure?>(
            (_) => null,
            onError: (Object e) => e as UploadBatchFailure,
          );

      expect(q.requests, hasLength(1));
      expect(failure!.statusCode, 409);
      expect(failure.landed, ['notes/a.txt']);
    });

    test('giving up reports what landed over every attempt', () async {
      final q = quark([
        const UploadBatchFailure(400, ['a.jpg']),
        const UploadBatchFailure(400, ['b.jpg']),
      ]);

      final failure =
          await sendUploadBatch(
            files: files(['a.jpg', 'b.jpg', 'c.jpg']),
            send: q.send,
            attempts: 2,
          ).then<UploadBatchFailure?>(
            (_) => null,
            onError: (Object e) => e as UploadBatchFailure,
          );

      expect(q.requests, [
        ['a.jpg', 'b.jpg', 'c.jpg'],
        ['b.jpg', 'c.jpg'],
      ]);
      expect(failure!.landed, ['a.jpg', 'b.jpg']);
    });

    test('a refusal that names nothing is not retried', () async {
      final q = quark([const ApiException(400)]);

      await expectLater(
        sendUploadBatch(files: files(['a.jpg']), send: q.send),
        throwsA(isA<ApiException>()),
      );
      expect(q.requests, hasLength(1));
    });
  });

  group('throwUploadFailure', () {
    test('reads the landed paths from the error body', () {
      expect(
        () => throwUploadFailure(
          409,
          '{"error":"name taken","landed":["notes/a.txt"]}',
          'upload',
        ),
        throwsA(
          isA<UploadBatchFailure>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.landed, 'landed', ['notes/a.txt']),
        ),
      );
    });

    test('an older Quark that names nothing is a plain ApiException', () {
      for (final body in ['{"error":"name taken"}', '', 'not json']) {
        expect(
          () => throwUploadFailure(409, body, 'upload'),
          throwsA(
            isA<ApiException>().having(
              (e) => e is UploadBatchFailure,
              'is a batch failure',
              false,
            ),
          ),
        );
      }
    });

    test('reads as any refused upload to the error copy', () {
      expect(
        Errors.message(const UploadBatchFailure(500, []), 'upload the photos'),
        Errors.message(const ApiException(500), 'upload the photos'),
      );
    });
  });
}
