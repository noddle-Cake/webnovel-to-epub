// Review-only fixtures; the installed app starts with an empty library.
// flutter test tool/preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/main.dart';

LibraryStore previewStore(AppAppearance appearance) => LibraryStore(
  appearance: appearance,
  novels: [
    for (final (index, title) in [
      'The Paper Kingdom',
      'A Sky Full of Letters',
      'The Last Winter Mage',
      'A Library Beyond the Stars',
      'The Clockmaker’s Daughter',
      'Where the Lanterns Go',
      'Letters from Another World',
      'The Quiet Alchemist',
    ].indexed)
      LibraryNovel(
        url: 'https://roliascan.com/manga/preview-$index',
        title: title,
        author: 'Sample Author',
        firstChapter: 'https://roliascan.com/read/preview/ch1/',
        addedAt: DateTime(2026, 1, index + 1),
        shelf: index % 3 == 0 ? 'Reading' : 'Plan to read',
        description: 'In a city that has forgotten how to dream, one young librarian discovers that every unwritten story is a doorway. Beyond the shelves, a world of impossible wonders is waiting. These are sample details for reviewing the interface.',
      ),
  ],
);
void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final name in ['DM Sans', 'Fraunces']) {
      final loader = FontLoader(name)
        ..addFont(
          rootBundle.load(
            'assets/fonts/${name == 'DM Sans' ? 'DMSans' : 'Fraunces'}.ttf',
          ),
        );
      await loader.load();
    }
  });
  for (final entry in {
    'desktop': (const Size(1280, 900), AppAppearance.dark),
    'phone': (const Size(390, 844), AppAppearance.dark),
    'phone-light': (const Size(390, 844), AppAppearance.light),
    'ereader-light': (const Size(390, 844), AppAppearance.ereaderLight),
    'ereader-dark': (const Size(390, 844), AppAppearance.ereaderDark),
    'detail': (const Size(390, 844), AppAppearance.dark),
  }.entries) {
    testWidgets('${entry.key} preview', (tester) async {
      tester.view.physicalSize = entry.value.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = previewStore(entry.value.$2);
      await tester.pumpWidget(NovelApp(store: store));
      await tester.pumpAndSettle();
      if (entry.key == 'detail') {
        await tester.tap(find.byKey(ValueKey(store.novels.last.url)));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(NovelApp),
        matchesGoldenFile('../screenshots/${entry.key}.png'),
      );
    });
  }
}
