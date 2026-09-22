import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Every user-facing error string in the app is produced here (#1622).
///
/// Pages and widgets must never build error copy themselves, and must never
/// put a thrown object into text a user reads. `'Save failed: $e'` renders
/// exception class names, OS errno values and full request URIs into the UI —
/// it tells the user nothing they can act on and leaks internals while doing
/// it. Call [Errors.message] instead and pass what the app was trying to do.
///
/// Centralizing has a second payoff: these strings are the app's entire
/// user-facing error vocabulary in one file, so translating them later is a
/// matter of swapping the bodies here for generated `AppLocalizations`
/// lookups, not of hunting sixty interpolations across twenty pages.
///
/// To extend: add a `static` method here, never a string at the call site.
abstract final class Errors {
  /// A short sentence for [error], safe to show a user.
  ///
  /// [action] names what the app was doing, as a bare verb phrase that reads
  /// after "Couldn't" — `'save the file'`, `'load your photos'`, `'delete the
  /// album'`. Lowercase, no trailing period.
  static String message(Object? error, String action) {
    if (error == null) return couldNot(action);
    if (isQuarkUnreachableError(error)) return quarkDisconnectedInline;
    if (error is UnauthorizedException) return sessionExpired;
    if (error is MessageException) return _sentence(error.message);
    if (error is ApiException) return _forStatus(error.statusCode, action);
    return couldNot(action);
  }

  /// The Quark writes its own copy in lowercase fragments — "server busy,
  /// please retry". Reshape it so it reads like the rest of the app's text.
  static String _sentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    final capitalized = trimmed[0].toUpperCase() + trimmed.substring(1);
    return '.!?'.contains(capitalized[capitalized.length - 1])
        ? capitalized
        : '$capitalized.';
  }

  /// The fallback: what the app was doing, and that it didn't work.
  static String couldNot(String action) => "Couldn't $action.";

  /// The zero-config connect form's own failure: an address that never
  /// answered is a typo as often as it is a sleeping Quark.
  static const String couldNotConnect =
      'Could not connect. Check the address and try again.';

  /// Headline above a [message], where a page has room for both.
  static const String somethingWentWrong = 'Something went wrong';

  /// Terse form, for a collapsed row whose expanded body carries the detail.
  static const String loadFailedShort = 'Failed to load';

  /// Playback copy. The format is the file's, not the Quark's, so these say so
  /// rather than routing the user through a connection or server explanation.
  static const String unsupportedAudioFormat =
      'Unable to play this audio file. The format may not be supported by '
      'this browser.';

  static const String unplayableMedia =
      'Unable to play this media. The file may use an unsupported '
      'codec/profile.';

  static String unsupportedVideoFormat(String extension) =>
      "This video format ($extension) isn't supported for in-browser "
      'playback. Download the file to watch it locally.';

  /// Files dropped onto the Photos page that are not images. The page leaves
  /// them out rather than filling the library with them (#2214).
  static String notPhotos(int count) => count == 1
      ? "1 file isn't a photo, so it wasn't uploaded."
      : "$count files aren't photos, so they weren't uploaded.";

  /// An album name a sibling already has, ignoring case — what the Quark's
  /// 409 means for creating, renaming or moving an album.
  static const String albumNameTaken =
      "There's already an album with that name here.";

  /// An album name with a `/` in it, which the Quark refuses with a 400.
  static const String albumNameHasSlash = "Album names can't contain a slash.";

  /// A file or folder name that is nothing but spaces, or nothing at all.
  static const String nameBlank = "The name can't be blank.";

  /// A spreadsheet tab name another tab in the same sheet has, ignoring case.
  static const String sheetNameTaken =
      "There's already a sheet with that name here.";

  /// A file or folder name longer than a filesystem allows one name to be.
  static const String nameTooLong = 'That name is too long. Try a shorter one.';

  /// A failed album create, rename or move. A 409 gets [albumNameTaken] — the
  /// generic "it changed while you were working" would send the user to retry
  /// a name that will clash again. [action] is as in [message].
  static String album(Object? error, String action) =>
      error is ApiException && error.statusCode == 409
      ? albumNameTaken
      : message(error, action);

  /// An upload the Quark refused with a 409: something in that folder
  /// already has the name. The user answers it by keeping both or replacing.
  static const String fileNameTaken =
      "There's already a file with that name here.";

  /// A failed upload or new file. A 409 gets [fileNameTaken] — the generic
  /// "it changed while you were working" would send the user to retry a name
  /// that will clash again. [action] is as in [message].
  static String upload(Object? error, String action) =>
      error is ApiException && error.statusCode == 409
      ? fileNameTaken
      : message(error, action);

  /// A restore the Quark refused with a 409: the item's original path is
  /// taken, and a restore never overwrites.
  static const String restoreConflict =
      'Something is already at that location. Move or rename it, then '
      'restore again.';

  /// A failed restore from the trash. A 409 gets [restoreConflict] — the
  /// generic "it changed while you were working" would send the user to retry
  /// something that will fail the same way. [action] is as in [message].
  static String restore(Object? error, String action) =>
      error is ApiException && error.statusCode == 409
      ? restoreConflict
      : message(error, action);

  /// Converting a video runs ffmpeg on the Quark, which answers 501 when it
  /// isn't installed. Nothing the user retries will change that.
  static const String ffmpegMissing =
      "Converting videos needs ffmpeg, which isn't installed on your Quark.";

  /// A conversion or retry refused with a 403. The output lands beside the
  /// video, so the account has to be able to save files in its folder.
  static const String cantSaveInFolder = "You can't save files in that folder.";

  /// A conversion that could not be started. A 501 gets [ffmpegMissing]
  /// rather than the generic "doesn't support that yet", and a 403
  /// [cantSaveInFolder].
  static String transcode(Object? error) => switch (error) {
    ApiException(statusCode: 501) => ffmpegMissing,
    ApiException(statusCode: 403) => cantSaveInFolder,
    _ => message(error, 'convert the video'),
  };

  /// A retry the Quark refused. Only a failed job can be retried, so a 409
  /// means this one didn't fail; a 422 means the file it used is gone; a 404
  /// means the Quark no longer knows the job, or no longer shows it to this
  /// account; a 403 means the account that queued it can't save files in the
  /// folder any more. Retrying again would fail the same way.
  static String retryJob(Object? error) => switch (error) {
    ApiException(statusCode: 409) => "That job can't be retried.",
    ApiException(statusCode: 422) => 'The file this job used no longer exists.',
    ApiException(statusCode: 404) => 'That job no longer exists.',
    ApiException(statusCode: 403) => cantSaveInFolder,
    _ => message(error, 'retry the job'),
  };

  /// A cancel the Quark refused: a 409 means the job had already finished, a
  /// 404 that the Quark no longer knows it or no longer shows it to this
  /// account. A 403 reads as the generic permission copy from [message].
  static String cancelJob(Object? error) => switch (error) {
    ApiException(statusCode: 409) => 'That job has already finished.',
    ApiException(statusCode: 404) => 'That job no longer exists.',
    _ => message(error, 'cancel the job'),
  };

  /// A job that failed on the Quark. [action] is what it was doing, as in
  /// [message]: `'convert vacation.mkv to MOV'`. A kind the app has no words
  /// for passes null and the job's own [name] is used instead. The job's
  /// error text is a diagnostic and never reaches this copy.
  static String jobFailed({required String? action, required String name}) =>
      action != null
      ? couldNot(action)
      : name.isEmpty
      ? couldNot('finish a job')
      : "$name didn't finish.";

  /// Remote access is switched on but the Quark could not start it. The
  /// Quark's own reason is a diagnostic from the network layer, so it goes to
  /// the log and the user reads this instead.
  static const String remoteAccessFailing =
      "Remote access is on, but your Quark couldn't start it. Its log has "
      'the details.';

  /// Demo mode's sample albums are bundled with the app, so there is no Quark
  /// to change them on.
  static const String demoModeReadOnly =
      "Sample albums can't be changed in demo mode.";

  /// Why SSH access can't be managed on this Quark, and what fixes it.
  /// [reason] is the code `GET /api/v0/ssh/status` sends (#2131).
  static String sshUnavailable(String? reason) => switch (reason) {
    'unsupported_os' =>
      'SSH access can only be managed on a Quark running Linux.',
    'not_service' =>
      "Quark isn't running as its installed service. On the device, run "
          '`sudo quark install`, then manage SSH access here.',
    'sshd_missing' =>
      "The SSH server isn't installed. On the device, run "
          '`sudo apt install openssh-server`, then `sudo quark install`.',
    'helper_missing' =>
      "Quark's SSH helper isn't installed yet. On the device, run "
          '`sudo quark install` to add it.',
    'no_login_shell' =>
      "The quark account can't sign in yet. On the device, run "
          '`sudo quark install` to give it a login shell.',
    _ => "SSH access can't be managed on this Quark.",
  };

  /// Session gone. The router sends the user to login on the next navigation;
  /// this is what they read in the meantime.
  static const String sessionExpired = 'Your session expired. Sign in again.';

  /// Removing, turning off or deleting the only active admin, which the Quark
  /// refuses with a 409.
  static const String lastAdmin =
      'This Quark needs at least one admin. Make someone else an admin first.';

  /// Signing in to an account someone requested that no admin has approved
  /// yet. The Quark refuses it with a 403 whose `status` is `pending`.
  static const String accountPending =
      "Your account request hasn't been approved yet. Ask an admin of this "
      'Quark.';

  /// Signing in to an account an admin turned off: a 403 whose `status` is
  /// `disabled`.
  static const String accountDisabled =
      'This account is turned off. Ask an admin of this Quark.';

  /// Requesting an account from a Quark that is not taking requests, which it
  /// answers with a 404.
  static const String accessRequestsOff =
      "This Quark isn't taking account requests right now.";

  /// A username a new account can't have. The Quark refuses it with a 400.
  static const String invalidUsername =
      'Use up to 32 lowercase letters, numbers, dots, dashes or underscores, '
      'starting with a letter or number.';

  /// Adding an account to a group, which the Quark refuses with a 404 when
  /// the account can't sign in: waiting for approval, turned off, or gone.
  static const String cannotJoinGroup =
      "That account can't join a group. Only accounts that can sign in can be "
      'added.';

  /// The Quark answered, and what it said maps to copy worth the difference.
  /// Anything unmapped falls back to [couldNot] — a vague-but-true sentence
  /// beats a guess about a status the backend may not even return.
  static String _forStatus(int statusCode, String action) =>
      switch (statusCode) {
        401 => sessionExpired,
        403 => "You don't have permission to $action.",
        404 => "Couldn't $action — it's no longer there.",
        409 =>
          "Couldn't $action — it changed while you were working. Try again.",
        429 => 'Too many requests. Wait a moment and try again.',
        501 => "Your Quark doesn't support that yet.",
        503 => 'Your Quark is busy. Try again in a moment.',
        _ when statusCode >= 500 => 'Your Quark ran into a problem. Try again.',
        _ => couldNot(action),
      };
}

/// A failure whose text was written for a user to read.
///
/// Throw this from a service when the message itself is the useful part —
/// "Invalid username or password." — and [Errors.message] will pass it
/// through untouched. Everything else should be an [ApiException] or a plain
/// [Exception], whose text is for logs only.
class MessageException implements Exception {
  final String message;
  const MessageException(this.message);

  @override
  String toString() => message;
}

/// The Quark answered with a non-success status.
///
/// Carries the code so [Errors.message] can say something specific. The
/// [toString] is for `debugPrint` and crash logs, never for the UI.
class ApiException implements Exception {
  final int statusCode;

  /// What the caller was requesting, for logs — `'load photos'`.
  final String? context;

  const ApiException(this.statusCode, [this.context]);

  @override
  String toString() =>
      'ApiException($statusCode)${context == null ? '' : ': $context'}';
}

/// Throws the right exception for a response the Quark refused: its own
/// message when it sent one, its status code otherwise.
///
/// The Quark's `error` field is hand-written copy, never a Go error's text, so
/// it is safe to put in front of a user — [Errors.message] tidies it into a
/// sentence. [context] is for logs only.
Never throwApiError(int statusCode, Object? serverMessage, String context) {
  if (serverMessage is String && serverMessage.trim().isNotEmpty) {
    throw MessageException(serverMessage.trim());
  }
  throw ApiException(statusCode, context);
}
