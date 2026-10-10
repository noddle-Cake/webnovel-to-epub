import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/library/novel_detail_screen.dart';
import 'package:novel_to_epub/main.dart';
import 'package:novel_to_epub/data/novel_service.dart';

import 'widget_test.dart' show fakeApi;

LibraryNovel fixture(
  String title, {
  String shelf = 'Plan to read',
}) => LibraryNovel(
  url:
      'https://roliascan.com/manga/${title.toLowerCase().replaceAll(' ', '-')}',
  title: title,
  author: 'An author',
  firstChapter: 'https://roliascan.com/read/sample/ch1/',
  addedAt: DateTime(2026, 1, 1),
  shelf: shelf,
  description: 'A journey through a world of stories.',
);

void main() {
  testWidgets('fresh install has an empty library and Moonleaf branding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NovelApp());
    await tester.pumpAndSettle();
    expect((await LibraryStore.load()).novels, isEmpty);
    expect(find.text('Your next story starts here'), findsOneWidget);
    expect(find.byKey(const Key('library-grid')), findsNothing);
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Moonleaf'), findsOneWidget);
  });

  test(
    'library, shelves, history and e-reader preference survive reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LibraryStore.load();
      await store.add(
        'https://roliascan.com/manga/sample/#top',
        const BookMetadata(
          title: 'Sample',
          author: 'Writer',
          firstChapter: 'https://roliascan.com/read/sample/ch1/',
        ),
      );
      await store.add(
        'https://roliascan.com/manga/sample',
        const BookMetadata(title: 'Duplicate'),
      );
      expect(store.novels.length, 1);
      final url = store.novels.single.url;
      await Future.wait([
        store.setShelf(url, 'Reading'),
        store.opened(url),
        store.setAppearance(theme: AppAppearance.ereaderDark, grid: false),
      ]);
      final reloaded = await LibraryStore.load();
      expect(reloaded.novels.single.title, 'Sample');
      expect(reloaded.novels.single.shelf, 'Reading');
      expect(reloaded.novels.single.openedAt, isNotNull);
      expect(reloaded.appearance, AppAppearance.ereaderDark);
      expect(reloaded.grid, isFalse);
      await reloaded.remove(url);
      expect((await LibraryStore.load()).novels, isEmpty);
    },
  );
  testWidgets('add from source, open detail, change shelf and see history', (
    tester,
  ) async {
    final store = LibraryStore();
    final api = fakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(NovelApp(store: store, service: api));
    await tester.tap(find.text('Browse sources'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add novel URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-novel-url')),
      'https://roliascan.com/manga/sample/',
    );
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(store.novels.single.title, 'A Sample Novel');
    await tester.tap(find.byKey(ValueKey(store.novels.single.url)));
    await tester.pumpAndSettle();
    expect(find.byType(NovelDetailScreen), findsOneWidget);
    expect(find.text('Synopsis'), findsOneWidget);
    await tester.tap(find.text('Change shelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(store.novels.single.shelf, 'Reading');
    await tester.tap(find.text('Create EPUB'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('book-title')))
          .controller!
          .text,
      'A Sample Novel',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    expect(find.text('RECENTLY OPENED'), findsOneWidget);
    expect(find.text('A Sample Novel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search and list view work on desktop', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LibraryStore(
      novels: [fixture('Paper Kingdom'), fixture('Winter Roads')],
    );
    await tester.pumpWidget(NovelApp(store: store));
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.byTooltip('Search library'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('library-search')), 'winter');
    await tester.pumpAndSettle();
    expect(find.text('Winter Roads'), findsWidgets);
    expect(find.text('Paper Kingdom'), findsNothing);
    await tester.tap(find.byTooltip('Library display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cover grid'));
    await tester.pumpAndSettle();
    expect(store.grid, isFalse);
    expect(tester.takeException(), isNull);
  });
  for (final appearance in [
    AppAppearance.ereaderLight,
    AppAppearance.ereaderDark,
  ]) {
    testWidgets(
      '${appearance.name} is monochrome, high contrast and reduced motion',
      (tester) async {
        final store = LibraryStore();
        await tester.pumpWidget(NovelApp(store: store));
        await tester.tap(find.byTooltip('Appearance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appearance-${appearance.name}')));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(NavigationBar));
        expect(
          Theme.of(context).colorScheme.surface,
          appearance == AppAppearance.ereaderDark ? Colors.black : Colors.white,
        );
        expect(MediaQuery.of(context).disableAnimations, isTrue);
        expect(find.byType(ColorFiltered), findsWidgets);
        expect(store.appearance, appearance);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'narrow phone with large type supports library, details and appearance',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final novel = fixture(
        'A Rather Long Light Novel Title About a Quiet Library',
      );
      final store = LibraryStore(novels: [novel]);
      await tester.pumpWidget(NovelApp(store: store));
      await tester.tap(find.byKey(ValueKey(novel.url)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
