import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/upload_config.dart';

/// A multipart upload the Quark refused partway through its batch (#3533).
///
/// [landed] holds the files-relative path of each file that landed before the
/// failure, in the order they were sent. The Quark writes a batch in order and
/// stops at the first failure, so the first `landed.length` files are the ones
/// that made it and everything after them did not. A retry resends only what
/// follows them, rather than landing the first ones again as keepBoth `_(1)`
/// copies.
///
/// It is an [ApiException], so [Errors.message] and a 409 check read it as
/// they read any refused upload.
class UploadBatchFailure extends ApiException {
  /// The Quark's answer, [statusCode], with the paths it said had [landed].
  const UploadBatchFailure(super.statusCode, this.landed, [super.context]);

  /// Where each file that made it landed, in the order sent.
  final List<String> landed;

  @override
  String toString() => '${super.toString()} (landed ${landed.length})';
}

/// Throws what a refused upload answered with [statusCode] and [body]: an
/// [UploadBatchFailure] when the body names the files that landed, a plain
/// [ApiException] from a Quark too old to say.
Never throwUploadFailure(int statusCode, String body, String context) {
  Object? decoded;
  try {
    decoded = body.isEmpty ? null : jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  final landed = decoded is Map<String, dynamic> ? decoded['landed'] : null;
  if (landed is List) {
    throw UploadBatchFailure(
      statusCode,
      landed.whereType<String>().toList(),
      context,
    );
  }
  throw ApiException(statusCode, context);
}

/// Builds one file's parts afresh: the file, and any thumbnail that follows it.
///
/// Called once per attempt, because a multipart part's body is a stream that
/// can only be read once.
typedef UploadBatchFile = Future<List<http.MultipartFile>> Function();

/// Sends [files] in one request through [send], and when the Quark refuses it
/// partway, sends again only the files it did not report as landed (#3533).
///
/// Retries a cut-off body (400) or a Quark that failed (5xx), up to
/// [attempts] requests in all. Any other refusal, a 409 among them, is the
/// caller's to answer, so it is thrown at once. Returns where each file
/// landed, in the order of [files]. A failure that ends the batch is thrown
/// as an [UploadBatchFailure] whose `landed` covers every attempt, so a caller
/// that resends after it skips those files too.
Future<List<String>> sendUploadBatch({
  required List<UploadBatchFile> files,
  required Future<List<String>> Function(List<http.MultipartFile> parts) send,
  int attempts = UploadConfig.maxBatchAttempts,
}) async {
  final landed = <String>[];
  var unsent = files;
  for (var attempt = 1; ; attempt++) {
    final parts = [for (final file in unsent) ...await file()];
    try {
      return landed..addAll(await send(parts));
    } on UploadBatchFailure catch (e) {
      landed.addAll(e.landed);
      unsent = unsent.sublist(e.landed.length.clamp(0, unsent.length));
      final retryable = e.statusCode == 400 || e.statusCode >= 500;
      if (!retryable || attempt >= attempts || unsent.isEmpty) {
        throw UploadBatchFailure(e.statusCode, List.of(landed), e.context);
      }
    }
  }
}
