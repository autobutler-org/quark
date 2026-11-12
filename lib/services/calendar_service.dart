import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/models/calendar_event.dart';
import 'package:quark/models/calendar_move.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/local_time_zone.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Calls `/api/v0/calendar/events`: the household calendar's events, listed by
/// range, created, updated, moved and deleted (#1144, #3215), and
/// `/api/v0/calendar/ical`: the subscription link other calendar apps poll, the
/// same feed as a one-time download, and the .ics import (#1151).
class CalendarService with AuthenticatedService {
  static final CalendarService _instance = CalendarService._();
  CalendarService._();
  static CalendarService get instance => _instance;

  /// api: none
  static Uri _apiUri(String path) => apiBaseUri.replace(path: '/api/v0$path');

  /// The events with an occurrence that may fall in [from, to): one-off events
  /// overlapping it, and every repeating series that starts before [to].
  ///
  /// api: GET /api/v0/calendar/events
  static Future<List<CalendarEvent>> listEvents(
    DateTime from,
    DateTime to,
  ) async {
    final uri = _apiUri('/calendar/events').replace(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'load calendar events');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return (data['events'] as List<dynamic>? ?? const [])
        .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Saves [draft]: creates an event, or with [id] replaces that event's
  /// fields (every occurrence of a repeating one).
  ///
  /// api: POST /api/v0/calendar/events
  /// api: PUT /api/v0/calendar/events/{id}
  static Future<CalendarEvent> saveEvent(
    CalendarEventDraft draft, {
    int? id,
    List<DateTime> excludedStarts = const [],
  }) async {
    final body = json.encode(
      CalendarEvent.requestBody(
        draft,
        timeZone: await localTimeZoneName(),
        excludedStarts: excludedStarts,
      ),
    );
    const headers = {'Content-Type': 'application/json'};
    final response = id == null
        ? await instance.authenticatedPost(
            _apiUri('/calendar/events'),
            headers: headers,
            body: body,
          )
        : await instance.authenticatedPut(
            _apiUri('/calendar/events/$id'),
            headers: headers,
            body: body,
          );
    if (response.statusCode != (id == null ? 201 : 200)) {
      throw ApiException(response.statusCode, 'save calendar event');
    }
    return CalendarEvent.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// Moves event [id]. [occurrenceStart] is the start of the occurrence that
  /// moved, and [start] and [end] are where it was dropped, all on the local
  /// clock. [scope] says whether that one, that one and every one after it,
  /// or the whole series moves.
  ///
  /// api: POST /api/v0/calendar/events/{id}/move
  static Future<CalendarMoveResult> moveEvent({
    required int id,
    required CalendarMoveScope scope,
    required DateTime occurrenceStart,
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await instance.authenticatedPost(
      _apiUri('/calendar/events/$id/move'),
      headers: const {'Content-Type': 'application/json'},
      body: json.encode({
        'scope': scope.name,
        'occurrenceStart': occurrenceStart.toUtc().toIso8601String(),
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'move calendar event');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final created = data['created'];
    return CalendarMoveResult(
      series: CalendarEvent.fromJson(data['series'] as Map<String, dynamic>),
      created: created is Map<String, dynamic>
          ? CalendarEvent.fromJson(created)
          : null,
    );
  }

  /// Deletes event [id], every occurrence of it included.
  ///
  /// api: DELETE /api/v0/calendar/events/{id}
  static Future<void> deleteEvent(int id) async {
    final response = await instance.authenticatedDelete(
      _apiUri('/calendar/events/$id'),
    );
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, 'delete calendar event');
    }
  }

  /// The link Apple Calendar, Google Calendar or Thunderbird subscribes to. It
  /// carries the caller's session token.
  ///
  /// api: GET /api/v0/calendar/ical/url
  static Future<String> subscriptionUrl() async {
    final response = await instance.authenticatedGet(
      _apiUri('/calendar/ical/url'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'load the subscription link');
    }
    return (json.decode(response.body) as Map<String, dynamic>)['url']
        as String;
  }

  /// The calendar as one .ics file, for a one-time import into an app that
  /// cannot reach the Quark. Small: it holds what the household typed in.
  ///
  /// api: GET /api/v0/calendar/ical
  static Future<Uint8List> downloadICal() async {
    final response = await instance.authenticatedGet(_apiUri('/calendar/ical'));
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'download the calendar');
    }
    return response.bodyBytes;
  }

  /// Adds the events in the iCalendar file [bytes]. Events already on the
  /// calendar and repeats it cannot represent are counted as skipped.
  ///
  /// api: POST /api/v0/calendar/ical
  static Future<({int imported, int skipped})> importICal(
    Uint8List bytes,
  ) async {
    final response = await instance.authenticatedPost(
      _apiUri('/calendar/ical'),
      headers: const {'Content-Type': 'text/calendar'},
      body: bytes,
    );
    // A 400 says the file is not an iCalendar; a 5xx carries a Go error's
    // text, so only client errors reach the user in the Quark's words.
    throwUnlessOk(response, 'import the calendar', clientErrorsOnly: true);
    final data = json.decode(response.body) as Map<String, dynamic>;
    return (
      imported: data['imported'] as int? ?? 0,
      skipped: data['skipped'] as int? ?? 0,
    );
  }
}
