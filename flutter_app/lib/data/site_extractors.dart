import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'novel_service.dart';

class NovelChapter {
  const NovelChapter(this.title, this.content, this.url, this.next);
  final String title;
  final String content;
  final Uri url;
  final Uri? next;
}

/// Add a site's parser here and register it in [extractorFor].
abstract class SiteExtractor {
  const SiteExtractor();
  BookMetadata book(String source, Uri url);
  NovelChapter chapter(String source, Uri url, int number);
}

SiteExtractor extractorFor(Uri url) {
  if (!['http', 'https'].contains(url.scheme) || url.userInfo.isNotEmpty) {
    throw const ApiException('Enter an HTTP or HTTPS novel URL.');
  }
  switch (url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '')) {
    case 'roliascan.com':
      return const RoliaExtractor();
    case 'royalroad.com':
      return const RoyalRoadExtractor();
    default:
      throw const ApiException(
        'This site is not supported. Choose Royal Road or RoliaScan.',
      );
  }
}

Uri? resolveLink(Uri base, String? href) {
  if (href == null || href.trim().isEmpty || href.startsWith('#')) return null;
  final url = base.resolve(href.trim());
  return ['http', 'https'].contains(url.scheme) ? url.removeFragment() : null;
}

List<Map<String, dynamic>> structuredData(Document doc) {
  final result = <Map<String, dynamic>>[];
  void visit(dynamic value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
    if (value is Map<String, dynamic>) {
      result.add(value);
      visit(value['@graph']);
    }
  }

  for (final script in doc.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    try {
      visit(jsonDecode(script.text));
    } on FormatException {
      /* Ignore malformed site metadata. */
    }
  }
  return result;
}

String valueText(dynamic value, String key) {
  if (value is String) return value;
  if (value is List) {
    return value
        .map((v) => valueText(v, key))
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
  if (value is Map) return valueText(value[key], key);
  return '';
}

NovelChapter parseChapter(
  Document doc,
  Uri url,
  int number,
  String selector,
  Element? next,
) {
  final content = doc.querySelector(selector);
  if (content == null) {
    throw const ApiException(
      'No readable chapter text found. This chapter may be restricted or image-only.',
    );
  }
  for (final element in content.querySelectorAll(
    'script,style,iframe,form,.rolia-ad-slot',
  )) {
    element.remove();
  }
  if (content.text.trim().isEmpty) {
    throw const ApiException('This chapter has no readable text.');
  }
  final title = doc.querySelector('h1')?.text.trim();
  return NovelChapter(
    title == null || title.isEmpty ? 'Chapter $number' : title,
    content.innerHtml,
    url,
    resolveLink(url, next?.attributes['href']),
  );
}

class RoliaExtractor extends SiteExtractor {
  const RoliaExtractor();
  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final data =
        structuredData(doc)
            .where(
              (d) =>
                  d['@type'] == 'Book' ||
                  (d['@type'] is List && (d['@type'] as List).contains('Book')),
            )
            .firstOrNull ??
        {};
    final first = resolveLink(
      url,
      doc
          .querySelector(
            'a#start-reading-btn[href],a.mobile-start-reading-btn[href]',
          )
          ?.attributes['href'],
    );
    final image = valueText(data['image'], 'url');
    return BookMetadata(
      title:
          doc.querySelector('h1')?.text.trim() ??
          valueText(data['name'], 'name'),
      author: valueText(data['author'], 'name'),
      firstChapter: first?.toString() ?? '',
      coverUrl: resolveLink(
        url,
        image.isEmpty
            ? doc
                  .querySelector('meta[property="og:image"]')
                  ?.attributes['content']
            : image,
      )?.toString(),
      description:
          doc.querySelector('#description-content-tab')?.text.trim() ??
          valueText(data['description'], 'description'),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    final next =
        doc.querySelector(
          'a[title="Next Chapter"][href],a[rel~="next"][href]',
        ) ??
        doc
            .querySelectorAll('a[href]')
            .where(
              (a) => (a.attributes['title'] ?? '').startsWith('Next: Chapter'),
            )
            .firstOrNull;
    return parseChapter(doc, url, number, '.reader-text', next);
  }
}

class RoyalRoadExtractor extends SiteExtractor {
  const RoyalRoadExtractor();
  @override
  BookMetadata book(String source, Uri url) {
    final doc = html.parse(source);
    final data =
        structuredData(doc).where((d) => d['name'] != null).firstOrNull ?? {};
    String? href = doc
        .querySelector('#chapters tbody a[href*="/chapter/"]')
        ?.attributes['href'];
    final action = data['potentialAction'];
    if (href == null && action is Map && action['target'] is Map) {
      href = action['target']['urlTemplate'] as String?;
    }
    return BookMetadata(
      title: valueText(data['name'], 'name').isNotEmpty
          ? valueText(data['name'], 'name')
          : doc.querySelector('h1')?.text.trim() ?? '',
      author:
          doc.querySelector('a[href^="/profile/"]')?.text.trim() ??
          valueText(data['author'], 'name'),
      firstChapter: resolveLink(url, href)?.toString() ?? '',
      coverUrl: resolveLink(
        url,
        valueText(data['thumbnailUrl'], 'url'),
      )?.toString(),
    );
  }

  @override
  NovelChapter chapter(String source, Uri url, int number) {
    final doc = html.parse(source);
    final next =
        doc.querySelector('a[rel~="next"][href]') ??
        doc
            .querySelectorAll('a[href*="/chapter/"]')
            .where((a) => a.text.trim().toLowerCase() == 'next chapter')
            .firstOrNull;
    return parseChapter(doc, url, number, '.chapter-content', next);
  }
}

/// Prevent a navigation link from silently extracting a different novel.
bool sameNovel(Uri first, Uri next) {
  String host(Uri u) =>
      u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (host(first) != host(next) ||
      !['http', 'https'].contains(next.scheme) ||
      next.userInfo.isNotEmpty) {
    return false;
  }
  final a = first.pathSegments.where((s) => s.isNotEmpty).toList();
  final b = next.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host(first) == 'roliascan.com') {
    return a.length >= 3 &&
        b.length >= 3 &&
        a[0] == 'read' &&
        b[0] == 'read' &&
        a[1] == b[1];
  }
  return a.length >= 4 &&
      b.length >= 4 &&
      a[0] == 'fiction' &&
      b[0] == 'fiction' &&
      a[1] == b[1] &&
      b.contains('chapter');
}
