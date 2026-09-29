import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/calendar_event.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/calendar_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The calendar routes and the event's wire shape (#1147).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  void answer(int status, Object? body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  const vet = {
    'id': 14,
    'calendarId': 1,
    'title': 'Vet',
    'notes': '',
    'location': 'Riverside',
    'start': '2026-09-29T23:00:00Z',
    'end': '2026-09-29T23:45:00Z',
    'allDay': false,
    'timeZone': 'America/Los_Angeles',
    'repeat': 'weekly',
    'reminderMinutes': 30,
    'colorIndex': 2,
  };

  test('lists a range as UTC and reads the events', () async {
    answer(200, {
      'events': [vet],
    });

    final events = await CalendarService.listEvents(
      DateTime.utc(2026, 9, 27, 7),
      DateTime.utc(2026, 10, 4, 7),
    );

    final url = requests.single.url;
    expect(url.path, '/api/v0/calendar/events');
    expect(url.queryParameters['from'], '2026-09-27T07:00:00.000Z');
    expect(url.queryParameters['to'], '2026-10-04T07:00:00.000Z');
    final event = events.single;
    expect(event.id, 14);
    expect(event.repeat, CalendarRepeat.weekly);
    expect(event.reminderMinutes, 30);
    expect(event.start, DateTime.utc(2026, 9, 29, 23));
    expect(event.localStart, DateTime.utc(2026, 9, 29, 23).toLocal());
  });

  test('an all-day event reads as local dates', () {
    final rent = CalendarEvent.fromJson({
      ...vet,
      'allDay': true,
      'start': '2026-10-01T00:00:00Z',
      'end': '2026-10-02T00:00:00Z',
      'repeat': 'monthly',
    });
    expect(rent.localStart, DateTime(2026, 10, 1));
    expect(rent.localEnd, DateTime(2026, 10, 2));
    expect(rent.toDraft().lastDate, DateTime(2026, 10, 1));
  });

  test('an unknown repeat reads as none', () {
    expect(CalendarEvent.repeatFromWire('yearly'), CalendarRepeat.none);
  });

  test('creates with POST, sending local times as UTC', () async {
    answer(201, vet);
    final start = DateTime(2026, 9, 29, 16);

    await CalendarService.saveEvent(
      CalendarEventDraft(
        title: '  Vet ',
        start: start,
        end: start.add(const Duration(minutes: 45)),
        repeat: CalendarRepeat.weekly,
        reminderMinutes: 30,
        colorIndex: 2,
      ),
    );

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/api/v0/calendar/events');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['title'], 'Vet');
    expect(body['start'], start.toUtc().toIso8601String());
    expect(body['repeat'], 'weekly');
    expect(body['reminderMinutes'], 30);
    expect(body['colorIndex'], 2);
  });

  test('updates with PUT, sending all-day dates as midnight UTC', () async {
    answer(200, vet);

    await CalendarService.saveEvent(
      CalendarEventDraft.allDayOn(DateTime(2026, 10, 1)),
      id: 14,
    );

    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/v0/calendar/events/14');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['allDay'], isTrue);
    expect(body['start'], '2026-10-01T00:00:00.000Z');
    expect(body['end'], '2026-10-02T00:00:00.000Z');
    expect(body['reminderMinutes'], isNull);
  });

  test('deletes by id', () async {
    answer(204, null);
    await CalendarService.deleteEvent(14);
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v0/calendar/events/14');
  });

  test('a refusal throws ApiException', () async {
    answer(400, {'error': 'invalid event: a title is required'});
    await expectLater(
      CalendarService.saveEvent(CalendarEventDraft.at(DateTime(2026, 9, 29))),
      throwsA(isA<ApiException>()),
    );
    answer(500, null);
    await expectLater(
      CalendarService.listEvents(DateTime(2026), DateTime(2026, 2)),
      throwsA(isA<ApiException>()),
    );
  });
}
