import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

String defaultApiUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  if (kIsWeb && Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1') {
    return Uri.base.origin;
  }
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://localhost:8000';
}

class NovelApi {
  NovelApi({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultApiUrl(),
      _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  Uri _url(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/$path');

  Future<http.Response> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final request = http.Request(method, _url(path));
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400) {
        String message = 'The request failed. Please try again.';
        try {
          final detail =
              (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
          if (detail is String) message = detail;
          if (detail is List && detail.isNotEmpty) {
            message = 'Please check the book details and try again.';
          }
        } catch (_) {
          /* A proxy can return non-JSON errors. */
        }
        throw ApiException(message, statusCode: response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot connect to the server. Check your connection and server address.',
      );
    }
  }

  Future<BookMetadata> detect(String url) async => BookMetadata.fromJson(
    jsonDecode((await _request('POST', 'books/detect', {'url': url})).body)
        as Map<String, dynamic>,
  );

  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  }) async {
    final response = await _request('POST', 'jobs', {
      'url': url,
      'title': title,
      'author': author,
      'chapter_url': chapterUrl,
      if (cover != null) 'cover_base64': base64Encode(cover),
    });
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  Future<ExtractionJob> job(String id) async => ExtractionJob.fromJson(
    jsonDecode((await _request('GET', 'jobs/$id')).body)
        as Map<String, dynamic>,
  );
  Future<void> cancel(String id) async {
    await _request('DELETE', 'jobs/$id');
  }

  Future<Uint8List> download(String id) async =>
      (await _request('GET', 'jobs/$id/download')).bodyBytes;
  void close() => _client.close();
}
