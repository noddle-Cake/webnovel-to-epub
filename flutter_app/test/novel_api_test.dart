import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/data/novel_api.dart';

void main() {
  test('extract sends edited details and cover bytes to the API', () async {
    final api = NovelApi(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/api/jobs');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Edited Title');
        expect(body['cover_base64'], base64Encode([1, 2, 3]));
        return http.Response('{"id":"job-id"}', 202);
      }),
    );
    addTearDown(api.close);
    expect(
      await api.extract(
        url: 'https://roliascan.com',
        title: 'Edited Title',
        author: 'Author',
        chapterUrl: 'https://roliascan.com/read/sample/ch1/',
        cover: Uint8List.fromList([1, 2, 3]),
      ),
      'job-id',
    );
  });
  test('server errors become readable exceptions', () async {
    final api = NovelApi(
      client: MockClient(
        (_) async => http.Response('{"detail":"Unsupported site"}', 422),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.detect('https://example.test'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Unsupported site',
        ),
      ),
    );
  });
  test('metadata can be incomplete and still edited', () {
    final metadata = BookMetadata.fromJson({
      'title': 'Book',
      'author': null,
      'chapter_1': null,
    });
    expect(metadata.author, '');
    expect(metadata.firstChapter, '');
  });
}
