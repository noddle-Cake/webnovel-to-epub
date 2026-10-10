// Generate reviewable previews with:
// flutter test tool/preview_test.dart --update-goldens
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/main.dart';

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
    'desktop': const Size(1280, 1500),
    'phone': const Size(390, 2100),
  }.entries) {
    testWidgets('${entry.key} preview', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const NovelApp());
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(NovelApp),
        matchesGoldenFile('../screenshots/${entry.key}.png'),
      );
    });
  }
}
