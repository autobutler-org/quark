import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/login_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/widgets/login/sign_in_form.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// #3591: on web, Flutter puts a real `<input>` in the DOM only for the
/// focused field, plus one for every other field in that field's
/// [AutofillGroup]. With no group, focusing Username left no password input
/// for a password manager to fill, so picking a login filled the username
/// and nothing else.
void main() {
  final settings = AppSettings.instance;

  setUp(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
    await settings.addHost(
      HostEntry(name: 'Home', hostAddress: 'http://localhost:8094'),
    );
  });

  tearDown(() async {
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  /// The [AutofillGroup] the field labeled [label] registers with.
  AutofillGroupState? groupOf(WidgetTester tester, String label) {
    final editable = find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(EditableText),
    );
    return tester.state<EditableTextState>(editable).currentAutofillScope
        as AutofillGroupState?;
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$name: username and password share one autofill group', (
      tester,
    ) async {
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            onLoginSuccess: () {},
            checkStatus: () async => const AuthStatus(setupComplete: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignInForm), findsOneWidget);
      final group = groupOf(tester, 'Username');
      expect(group, isNotNull, reason: 'Username sits in no AutofillGroup');
      expect(groupOf(tester, 'Password'), same(group));

      final hints = [
        for (final client in group!.autofillClients)
          ...client.textInputConfiguration.autofillConfiguration.autofillHints,
      ];
      expect(
        hints,
        unorderedEquals([AutofillHints.username, AutofillHints.password]),
      );
    });
  }
}
