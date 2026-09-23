import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/utils/first_frame_gate.dart';

GoRouter routerWith(GoRouterRedirect redirect) => GoRouter(
  initialLocation: '/',
  redirect: redirect,
  routes: [GoRoute(path: '/', builder: (_, _) => const Text('page'))],
);

void main() {
  testWidgets('holds the first frame while the initial redirect is pending', (
    tester,
  ) async {
    final answer = Completer<String?>();
    final router = routerWith((_, _) => answer.future);
    addTearDown(router.dispose);

    deferFirstFrameUntilRouted(tester.binding, router.routerDelegate);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(tester.binding.sendFramesToEngine, isFalse);

    answer.complete(null);
    await tester.pumpAndSettle();

    expect(tester.binding.sendFramesToEngine, isTrue);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('lets the first frame through once a sync redirect routes', (
    tester,
  ) async {
    final router = routerWith((_, _) => null);
    addTearDown(router.dispose);

    deferFirstFrameUntilRouted(tester.binding, router.routerDelegate);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(tester.binding.sendFramesToEngine, isTrue);
    expect(find.text('page'), findsOneWidget);
  });
}
