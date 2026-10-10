// Optional live smoke check; downloads only two chapters, never the whole book.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/data/epub_writer.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/smoke_site.dart <novel-url>');
    exitCode = 64;
    return;
  }
  final url = Uri.parse(args.single);
  final client = http.Client();
  try {
    Future<String> fetch(Uri uri) async {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      return response.body;
    }

    final parser = extractorFor(url);
    final book = parser.book(await fetch(url), url);
    final chapters = <NovelChapter>[];
    var current = Uri.parse(book.firstChapter);
    for (var i = 0; i < 2; i++) {
      final chapter = parser.chapter(await fetch(current), current, i + 1);
      chapters.add(chapter);
      if (chapter.next == null) break;
      if (!sameNovel(current, chapter.next!)) {
        throw StateError('Invalid next link');
      }
      current = chapter.next!;
    }
    final bytes = buildEpub(EpubBook(book.title, book.author, chapters, null));
    final archive = ZipDecoder().decodeBytes(bytes);
    stdout.writeln(
      '${book.title}: ${chapters.length} chapters, ${archive.length} EPUB entries, ${bytes.length} bytes',
    );
  } finally {
    client.close();
  }
}
