import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xml/xml.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/data/epub_writer.dart';
import 'package:novel_to_epub/main.dart';
import 'package:novel_to_epub/library/library_store.dart';

const bookUrl = 'https://roliascan.com/manga/sample/';
const first = 'https://roliascan.com/read/sample/ch1/';
const second = 'https://roliascan.com/read/sample/ch2/';
const book =
    '''<h1>Sample</h1><script type="application/ld+json">{"@graph":[{"@type":"Book","author":{"name":"Author"},"image":"/cover.jpg"}]}</script><a id="start-reading-btn" href="/read/sample/ch1/">Read</a>''';
const chapter =
    '''<h1>Opening &amp; More</h1><div class="reader-text"><p>Hello&nbsp;<em>world</em><br>Next line</p><script>bad()</script></div><a title="Next Chapter" href="../ch2/">Next</a>''';
const last = '<h1>End</h1><div class="reader-text"><p>Done.</p></div>';

Future<ExtractionJob> finish(LocalNovelService service, String id) async {
  for (var i = 0; i < 500; i++) {
    final job = await service.job(id);
    if (!job.active) return job;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Job did not finish');
}

void main() {
  testWidgets('native app has no server connection setup', (tester) async {
    await tester.pumpWidget(NovelApp(store: LibraryStore()));
    expect(find.byTooltip('Server connection'), findsNothing);
  });
  test('local metadata, chapter requests and EPUB need no API', () async {
    final calls = <String>[];
    final service = LocalNovelService(
      client: MockClient((r) async {
        calls.add(r.url.toString());
        return http.Response(
          {bookUrl: book, first: chapter, second: last}[r.url.toString()]!,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.close);
    final metadata = await service.detect(bookUrl);
    expect(metadata.author, 'Author');
    expect(metadata.firstChapter, first);
    final id = await service.extract(
      url: bookUrl,
      title: 'Edited & title',
      author: 'A < B',
      chapterUrl: metadata.firstChapter,
    );
    final job = await finish(service, id);
    expect(job.error, isNull);
    expect(job.status, 'complete');
    expect(job.chapters, 2);
    expect(calls, [bookUrl, first, second]);
    final bytes = await service.download(id);
    // The first ZIP entry must be an uncompressed EPUB mimetype.
    expect(ByteData.sublistView(bytes).getUint16(8, Endian.little), 0);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.files.first.name, 'mimetype');
    expect(utf8.decode(zip.files.first.content), 'application/epub+zip');
    for (final file in zip.files.where(
      (f) =>
          f.name.endsWith('.xml') ||
          f.name.endsWith('.opf') ||
          f.name.endsWith('.xhtml'),
    )) {
      expect(
        () => XmlDocument.parse(utf8.decode(file.content)),
        returnsNormally,
        reason: file.name,
      );
    }
    final content = utf8.decode(
      zip.findFile('EPUB/chapter00001.xhtml')!.content,
    );
    expect(content, contains('<em>world</em>'));
    expect(content, isNot(contains('bad()')));
    final opf = XmlDocument.parse(
      utf8.decode(zip.findFile('EPUB/content.opf')!.content),
    );
    expect(opf.findAllElements('dc:title').single.innerText, 'Edited & title');
    expect(opf.findAllElements('itemref').length, 3);
  });
  for (final next in [
    first,
    'https://evil.test/ch2',
    'https://roliascan.com/read/another/ch2/',
  ]) {
    test('rejects loop or different novel: $next', () async {
      var requests = 0;
      final service = LocalNovelService(
        client: MockClient((r) async {
          requests++;
          return http.Response(
            '<div class="reader-text">Text</div><a rel="next" href="$next">Next</a>',
            200,
          );
        }),
      );
      addTearDown(service.close);
      final id = await service.extract(
        url: bookUrl,
        title: 'Title',
        author: 'Author',
        chapterUrl: first,
      );
      expect((await finish(service, id)).status, 'failed');
      expect(requests, 1);
      await expectLater(service.download(id), throwsA(isA<ApiException>()));
    });
  }
  test('cancel in-flight request never offers a partial EPUB', () async {
    final response = Completer<http.Response>();
    final service = LocalNovelService(
      client: MockClient((_) => response.future),
    );
    addTearDown(service.close);
    final id = await service.extract(
      url: bookUrl,
      title: 'Title',
      author: 'Author',
      chapterUrl: first,
    );
    await service.cancel(id);
    response.complete(http.Response(chapter, 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await service.job(id)).status, 'cancelled');
    await expectLater(service.download(id), throwsA(isA<ApiException>()));
  });
  test('missing content and spoofed domains fail explicitly', () {
    expect(
      () => extractorFor(Uri.parse('https://roliascan.com.evil.test')),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => const RoliaExtractor().chapter(
        '<h1>Blocked</h1>',
        Uri.parse(first),
        1,
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test('Royal Road metadata and navigation are supported', () {
    const parser = RoyalRoadExtractor();
    final url = Uri.parse('https://www.royalroad.com/fiction/123/title');
    final metadata = parser.book(
      '<h1>Title</h1><a href="/profile/1">Writer</a><table id="chapters"><tbody><tr><td><a href="/fiction/123/title/chapter/4/first">First</a></td></tr></tbody></table>',
      url,
    );
    expect(metadata.author, 'Writer');
    final first = Uri.parse(metadata.firstChapter);
    final chapter = parser.chapter(
      '<h1>First</h1><div class="chapter-content"><p>Text</p></div><a href="/fiction/123/title/chapter/5/second">Next Chapter</a>',
      first,
      1,
    );
    expect(sameNovel(first, chapter.next!), isTrue);
    expect(
      parser
          .chapter('<div class="chapter-content">End</div>', chapter.next!, 2)
          .next,
      isNull,
    );
  });
  test('EPUB embeds cover and safely names duplicate chapter titles', () {
    final bytes = buildEpub(
      EpubBook('Title', 'Author', [
        NovelChapter('../same', '<p>A</p>', Uri.parse(first), null),
        NovelChapter('../same', '<p>B</p>', Uri.parse(second), null),
      ], Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
    );
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('EPUB/cover.png'), isNotNull);
    expect(zip.findFile('EPUB/chapter00002.xhtml'), isNotNull);
    expect(
      utf8.decode(zip.findFile('EPUB/content.opf')!.content),
      contains('properties="cover-image"'),
    );
  });
}
