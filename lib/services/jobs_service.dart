import 'dart:convert';

import 'package:quark/models/job.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The long-running job API: `/api/v0/jobs`.
///
/// A refusal throws [ApiException] rather than going through [throwApiError]:
/// a job's error text is a diagnostic, not copy for a user, so the status code
/// is what [Errors] reads.
class JobsService with AuthenticatedService {
  JobsService._();
  static final JobsService instance = JobsService._();

  /// The jobs of the given [kinds] (see `JobKinds`), newest first. [kinds]
  /// must not be empty: the Quark rejects a listing that names no kind.
  static Future<List<Job>> listJobs({required List<String> kinds}) async {
    final uri = listJobsUri(apiBaseUri, kinds);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list jobs');
    }
    final data = jsonDecode(response.body) as List? ?? const [];
    return data.whereType<Map<String, dynamic>>().map(Job.fromJson).toList();
  }

  /// `GET /api/v0/jobs` on [base], with one repeated `kind` parameter per
  /// entry in [kinds]: `?kind=a&kind=b`. Throws [ArgumentError] when [kinds] is
  /// empty, which the Quark would answer with a 400.
  static Uri listJobsUri(Uri base, List<String> kinds) {
    if (kinds.isEmpty) {
      throw ArgumentError.value(kinds, 'kinds', 'must name at least one kind');
    }
    return base
        .resolve('/api/v0/jobs')
        .replace(queryParameters: {'kind': kinds});
  }

  /// One job by [id]. A 404 means the Quark no longer knows it.
  static Future<Job> getJob(int id) async {
    final uri = apiBaseUri.resolve('/api/v0/jobs/$id');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to get job');
    }
    return Job.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Puts failed job [id] back to pending. The job keeps its id, so there is
  /// nothing to return. A 409 means it didn't fail, a 422 that its files are
  /// gone, and a 404 that the Quark doesn't know it. Show a failure with
  /// `Errors.retryJob`.
  static Future<void> retryJob(int id) async {
    final uri = apiBaseUri.resolve('/api/v0/jobs/$id/retry');
    final response = await instance.authenticatedPost(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to retry job');
    }
  }

  /// Cancels job [id] and returns it as it now stands. A 409 means it had
  /// already finished.
  static Future<Job> cancelJob(int id) async {
    final uri = apiBaseUri.resolve('/api/v0/jobs/$id');
    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to cancel job');
    }
    return Job.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
