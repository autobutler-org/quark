import 'dart:convert';

import 'package:quark/models/calendar_event.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/local_time_zone.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Calls `/api/v0/calendar/events`: the household calendar's events, listed by
/// range, created, updated and deleted (#1144).
class CalendarService with AuthenticatedService {
  static final CalendarService _instance = CalendarService._();
  CalendarService._();
  static CalendarService get instance => _instance;

  static Uri _apiUri(String path) => apiBaseUri.replace(path: '/api/v0$path');

  /// The events with an occurrence that may fall in [from, to): one-off events
  /// overlapping it, and every repeating series that starts before [to].
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
  static Future<CalendarEvent> saveEvent(
    CalendarEventDraft draft, {
    int? id,
  }) async {
    final body = json.encode(
      CalendarEvent.requestBody(draft, timeZone: localTimeZoneName),
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

  /// Deletes event [id], every occurrence of it included.
  static Future<void> deleteEvent(int id) async {
    final response = await instance.authenticatedDelete(
      _apiUri('/calendar/events/$id'),
    );
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, 'delete calendar event');
    }
  }
}
