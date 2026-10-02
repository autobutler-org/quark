import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/sessions_controller.dart';
import 'package:quark/models/auth_session.dart';
import 'package:quark/utils/error_text.dart';

final _current = AuthSession(
  id: 'current',
  createdAt: DateTime.utc(2026, 9),
  lastUsedAt: DateTime.utc(2026, 9, 2),
  current: true,
);

final _other = AuthSession(
  id: 'other',
  createdAt: DateTime.utc(2026, 8),
  lastUsedAt: DateTime.utc(2026, 8, 2),
  current: false,
);

void main() {
  test('loads the sessions', () async {
    final controller = SessionsController(list: () async => [_current, _other]);
    expect(controller.hasOthers, isFalse);
    await controller.load();
    expect(controller.sessions, [_current, _other]);
    expect(controller.hasOthers, isTrue);
    expect(controller.error, isNull);
    expect(controller.isLoading, isFalse);
  });

  test('a failed load says so and keeps the list it had', () async {
    var fail = false;
    final controller = SessionsController(
      list: () async {
        if (fail) throw const ApiException(500);
        return [_current];
      },
    );
    await controller.load();
    fail = true;
    await controller.load();
    expect(
      controller.error,
      Errors.message(const ApiException(500), 'load your sessions'),
    );
    expect(controller.sessions, [_current]);
  });

  test('revoking another session reloads the list', () async {
    final calls = <String>[];
    var sessions = [_current, _other];
    final controller = SessionsController(
      list: () async {
        calls.add('list');
        return sessions;
      },
      revoke: (id) async {
        calls.add('revoke $id');
        sessions = [_current];
      },
      logout: () async => calls.add('logout'),
    );
    await controller.load();

    expect(await controller.revoke(_other), isTrue);
    expect(calls, ['list', 'revoke other', 'list']);
    expect(controller.sessions, [_current]);
    expect(controller.hasOthers, isFalse);
    expect(controller.isWorking, isFalse);
  });

  test('revoking the current session logs out instead', () async {
    final calls = <String>[];
    final controller = SessionsController(
      list: () async {
        calls.add('list');
        return [_current, _other];
      },
      revoke: (id) async => calls.add('revoke $id'),
      logout: () async => calls.add('logout'),
    );
    await controller.load();

    expect(await controller.revoke(_current), isTrue);
    // No revoke call and no reload: the token is gone, so both would be 401s.
    expect(calls, ['list', 'logout']);
  });

  test('revoking the others reloads the list', () async {
    final calls = <String>[];
    var sessions = [_current, _other];
    final controller = SessionsController(
      list: () async {
        calls.add('list');
        return sessions;
      },
      revokeOthers: () async {
        calls.add('revoke others');
        sessions = [_current];
      },
    );
    await controller.load();

    expect(await controller.revokeOthers(), isTrue);
    expect(calls, ['list', 'revoke others', 'list']);
    expect(controller.sessions, [_current]);
  });

  test('a failed revoke says so and keeps the list', () async {
    final controller = SessionsController(
      list: () async => [_current, _other],
      revoke: (_) async => throw const ApiException(404),
      revokeOthers: () async => throw const ApiException(500),
    );
    await controller.load();

    expect(await controller.revoke(_other), isFalse);
    expect(
      controller.error,
      Errors.message(const ApiException(404), 'sign out that session'),
    );
    expect(await controller.revokeOthers(), isFalse);
    expect(
      controller.error,
      Errors.message(const ApiException(500), 'sign out your other sessions'),
    );
    expect(controller.sessions, [_current, _other]);
    expect(controller.isWorking, isFalse);
  });
}
