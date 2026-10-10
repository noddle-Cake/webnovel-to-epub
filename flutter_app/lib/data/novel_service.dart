import 'dart:typed_data';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final int? statusCode;
  final String message;
  @override
  String toString() => message;
}

class BookMetadata {
  const BookMetadata({
    this.title = '',
    this.author = '',
    this.firstChapter = '',
    this.coverUrl,
    this.description,
  });
  final String title;
  final String author;
  final String firstChapter;
  final String? coverUrl;
  final String? description;

  factory BookMetadata.fromJson(Map<String, dynamic> json) => BookMetadata(
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    firstChapter: json['chapter_1'] as String? ?? '',
    coverUrl: json['cover_url'] as String?,
    description: json['description'] as String?,
  );
}

class ExtractionJob {
  const ExtractionJob({
    required this.id,
    required this.status,
    this.chapters = 0,
    this.chapterTitle = '',
    this.error,
  });
  final String id;
  final String status;
  final int chapters;
  final String chapterTitle;
  final String? error;
  bool get active => status == 'running' || status == 'queued';
  factory ExtractionJob.fromJson(Map<String, dynamic> json) => ExtractionJob(
    id: json['id'] as String,
    status: json['status'] as String,
    chapters: json['chapters'] as int? ?? 0,
    chapterTitle: json['chapter_title'] as String? ?? '',
    error: json['error'] as String?,
  );
}

abstract class NovelService {
  Future<BookMetadata> detect(String url);
  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  });
  Future<ExtractionJob> job(String id);
  Future<void> cancel(String id);
  Future<Uint8List> download(String id);
  void close();
}
