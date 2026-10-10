import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/main.dart';
import 'package:novel_to_epub/data/novel_api.dart';

NovelApi fakeApi({bool fail = false}) => NovelApi(
  client: MockClient((request) async {
    if (fail) {
      return http.Response(jsonEncode({'detail': 'Novel text missing.'}), 422);
    }
    if (request.url.path.endsWith('/detect')) {
      return http.Response(
        jsonEncode({
          'title': 'A Sample Novel',
          'author': 'Sample Author',
          'chapter_1': 'https://roliascan.com/read/sample/ch1/',
          'description': 'A story to take with you.',
        }),
        200,
      );
    }
    if (request.method == 'POST') return http.Response('{"id":"job-1"}', 202);
    return http.Response(
      '{"id":"job-1","status":"complete","chapters":2,"chapter_title":"The End"}',
      200,
    );
  }),
);

void main() {
  testWidgets('phone layout and form validation', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = fakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(NovelApp(service: api));
    expect(find.text('Chapter & Verse'), findsOneWidget);
    expect(find.text('Good stories.\nYours to keep.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('create-epub')));
    await tester.tap(find.byKey(const Key('create-epub')));
    await tester.pumpAndSettle();
    expect(find.text('Add a book title.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detect, edit, extract and offer download on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = fakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(NovelApp(service: api));
    await tester.enterText(
      find.byKey(const Key('novel-url')),
      'https://roliascan.com/manga/sample/',
    );
    await tester.tap(find.text('Find book details'));
    await tester.pumpAndSettle();
    expect(find.text('A Sample Novel'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('book-title')),
      'My Edited Title',
    );
    await tester.ensureVisible(find.byKey(const Key('create-epub')));
    await tester.tap(find.byKey(const Key('create-epub')));
    await tester.pumpAndSettle();
    expect(find.text('Your next read is ready.'), findsOneWidget);
    expect(find.text('2 chapters collected'), findsOneWidget);
    expect(find.byKey(const Key('save-epub')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API errors are shown without losing the form', (tester) async {
    final api = fakeApi(fail: true);
    addTearDown(api.close);
    await tester.pumpWidget(NovelApp(service: api));
    await tester.enterText(
      find.byKey(const Key('novel-url')),
      'https://roliascan.com/manga/sample/',
    );
    await tester.ensureVisible(find.text('Find book details'));
    await tester.tap(find.text('Find book details'));
    await tester.pumpAndSettle();
    expect(find.text('Novel text missing.'), findsOneWidget);
    expect(find.byKey(const Key('novel-url')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text on a narrow screen remains usable', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = fakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: NovelApp(service: api),
      ),
    );
    await tester.ensureVisible(find.text('Upload a cover'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('expired jobs release the form for another extraction', (
    tester,
  ) async {
    final api = NovelApi(
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/jobs')) {
          return http.Response('{"id":"expired"}', 202);
        }
        return http.Response('{"detail":"This extraction has expired."}', 404);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(NovelApp(service: api));
    await tester.enterText(
      find.byKey(const Key('novel-url')),
      'https://roliascan.com/manga/sample/',
    );
    await tester.enterText(find.byKey(const Key('book-title')), 'Sample');
    await tester.enterText(find.byKey(const Key('book-author')), 'Author');
    await tester.enterText(
      find.byKey(const Key('first-chapter')),
      'https://roliascan.com/read/sample/ch1/',
    );
    await tester.ensureVisible(find.byKey(const Key('create-epub')));
    await tester.tap(find.byKey(const Key('create-epub')));
    await tester.pumpAndSettle();
    expect(find.text('This extraction has expired.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('create-epub')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
