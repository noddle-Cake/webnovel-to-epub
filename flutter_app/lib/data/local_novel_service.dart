import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'epub_writer.dart';
import 'novel_service.dart';
import 'site_extractors.dart';

class _LocalJob {
  _LocalJob(this.id);
  final String id;
  String status = 'queued';
  String title = '';
  String? error;
  int chapters = 0;
  Uint8List? bytes;
  bool get cancelled => status == 'cancelled';
  ExtractionJob get snapshot => ExtractionJob(
    id: id,
    status: status,
    chapters: chapters,
    chapterTitle: title,
    error: error,
  );
}

/// Installed apps fetch and package books on the device. No API server is used.
class LocalNovelService implements NovelService {
  LocalNovelService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _jobs = <String, _LocalJob>{};
  int _sequence = 0;
  bool _closed = false;

  Future<String> _fetch(Uri uri) async {
    extractorFor(uri);
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw ApiException(
          'The novel site returned HTTP ${response.statusCode}. Try again later or check that the chapter is publicly readable.',
        );
      }
      return response.body;
    } on TimeoutException {
      throw const ApiException(
        'The novel site took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the novel site. Check your internet connection.',
      );
    }
  }

  @override
  Future<BookMetadata> detect(String url) async {
    final uri = Uri.parse(url);
    final parser = extractorFor(uri);
    final metadata = parser.book(await _fetch(uri), uri);
    if (metadata.firstChapter.isNotEmpty) {
      final first = Uri.parse(metadata.firstChapter);
      if (extractorFor(first).runtimeType != parser.runtimeType ||
          !sameNovel(first, first)) {
        throw const ApiException(
          'The site returned an invalid first chapter link.',
        );
      }
    }
    return metadata;
  }

  @override
  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  }) async {
    if (_closed) {
      throw const ApiException('The app has closed this extraction session.');
    }
    if (_jobs.values.any((j) => j.snapshot.active)) {
      throw const ApiException('Wait for the current extraction to finish.');
    }
    final parser = extractorFor(Uri.parse(url));
    final first = Uri.parse(chapterUrl).removeFragment();
    if (extractorFor(first).runtimeType != parser.runtimeType ||
        !sameNovel(first, first)) {
      throw const ApiException(
        'Choose a chapter URL from the same supported novel site.',
      );
    }
    if (title.trim().isEmpty) throw const ApiException('Enter a book title.');
    _jobs.clear();
    final job = _LocalJob('local-${++_sequence}');
    _jobs[job.id] = job;
    unawaited(_run(job, parser, first, title, author, cover));
    return job.id;
  }

  Future<void> _run(
    _LocalJob job,
    SiteExtractor parser,
    Uri first,
    String title,
    String author,
    Uint8List? cover,
  ) async {
    final chapters = <NovelChapter>[];
    final visited = <String>{};
    Uri? current = first;
    job.status = 'running';
    try {
      while (current != null) {
        if (_closed || job.cancelled) return;
        if (!sameNovel(first, current)) {
          throw const ApiException(
            'Stopped because the next link points outside this novel.',
          );
        }
        if (!visited.add(current.removeFragment().toString())) {
          throw const ApiException(
            'The site has a repeated chapter link. Extraction stopped to avoid a loop.',
          );
        }
        final source = await _fetch(current);
        if (_closed || job.cancelled) return;
        final chapter = parser.chapter(source, current, chapters.length + 1);
        chapters.add(chapter);
        job.chapters = chapters.length;
        job.title = chapter.title;
        current = chapter.next;
      }
      if (_closed || job.cancelled) return;
      final bytes = await compute(
        buildEpub,
        EpubBook(title, author, chapters, cover),
      );
      if (_closed || job.cancelled) return;
      job.bytes = bytes;
      job.status = 'complete';
    } catch (error) {
      if (_closed || job.cancelled) return;
      job.error = error is ApiException
          ? error.message
          : 'Could not create this book: $error';
      job.status = 'failed';
    }
  }

  _LocalJob _get(String id) =>
      _jobs[id] ??
      (throw const ApiException(
        'This extraction is no longer available.',
        statusCode: 404,
      ));
  @override
  Future<ExtractionJob> job(String id) async => _get(id).snapshot;
  @override
  Future<void> cancel(String id) async {
    final job = _get(id);
    if (job.snapshot.active) job.status = 'cancelled';
  }

  @override
  Future<Uint8List> download(String id) async =>
      _get(id).bytes ??
      (throw const ApiException('The EPUB is not ready yet.'));
  @override
  void close() {
    _closed = true;
    for (final job in _jobs.values) {
      if (job.snapshot.active) job.status = 'cancelled';
    }
    _client.close();
    _jobs.clear();
  }
}
