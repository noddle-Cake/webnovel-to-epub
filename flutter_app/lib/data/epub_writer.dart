import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'site_extractors.dart';

class EpubBook {
  const EpubBook(this.title, this.author, this.chapters, this.cover);
  final String title;
  final String author;
  final List<NovelChapter> chapters;
  final Uint8List? cover;
}

XmlElement element(
  String name, [
  Map<String, String> attrs = const {},
  List<XmlNode> children = const [],
]) => XmlElement(
  XmlName.qualified(name),
  attrs.entries
      .map((e) => XmlAttribute(XmlName.qualified(e.key), e.value))
      .toList(),
  children,
);
XmlElement textElement(String name, String value) =>
    element(name, {}, [XmlText(value)]);
String document(XmlElement root) =>
    XmlDocument([XmlProcessing('xml', 'version="1.0" encoding="UTF-8"'), root])
        .toXmlString();

/// HTML is parsed and rebuilt as well-formed XHTML, with no active content.
List<XmlNode> chapterNodes(String source, Uri base) {
  const allowed = {
    'p',
    'div',
    'span',
    'em',
    'strong',
    'b',
    'i',
    'u',
    's',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'ul',
    'ol',
    'li',
    'br',
    'hr',
    'pre',
    'code',
    'table',
    'thead',
    'tbody',
    'tr',
    'td',
    'th',
    'sup',
    'sub',
    'a',
  };
  const dropped = {
    'script',
    'style',
    'iframe',
    'form',
    'input',
    'button',
    'object',
    'embed',
    'svg',
  };
  List<XmlNode> convert(dom.Node node) {
    if (node is dom.Text) return [XmlText(node.data)];
    if (node is! dom.Element || dropped.contains(node.localName)) return [];
    final children = node.nodes.expand(convert).toList();
    if (!allowed.contains(node.localName)) return children;
    final attrs = <String, String>{};
    if (node.localName == 'a') {
      final href = resolveLink(base, node.attributes['href']);
      if (href != null) attrs['href'] = href.toString();
    }
    return [element(node.localName!, attrs, children)];
  }

  return html.parseFragment(source).nodes.expand(convert).toList();
}

Uint8List buildEpub(EpubBook book) {
  if (book.chapters.isEmpty) {
    throw ArgumentError('A book needs at least one chapter.');
  }
  final archive = Archive();
  void add(String path, String text) {
    final data = utf8.encode(text);
    archive.addFile(ArchiveFile(path, data.length, data));
  }

  final mime = utf8.encode('application/epub+zip');
  archive.addFile(
    ArchiveFile('mimetype', mime.length, mime)
      ..compression = CompressionType.none,
  );
  add(
    'META-INF/container.xml',
    document(
      element(
        'container',
        {
          'version': '1.0',
          'xmlns': 'urn:oasis:names:tc:opendocument:xmlns:container',
        },
        [
          element('rootfiles', {}, [
            element('rootfile', {
              'full-path': 'EPUB/content.opf',
              'media-type': 'application/oebps-package+xml',
            }),
          ]),
        ],
      ),
    ),
  );
  String xhtml(String title, List<XmlNode> children) => document(
    element(
      'html',
      {
        'xmlns': 'http://www.w3.org/1999/xhtml',
        'xmlns:epub': 'http://www.idpf.org/2007/ops',
        'lang': 'en',
      },
      [
        element('head', {}, [
          textElement('title', title),
          element('link', {
            'rel': 'stylesheet',
            'type': 'text/css',
            'href': 'style.css',
          }),
        ]),
        element('body', {}, children),
      ],
    ),
  );
  add(
    'EPUB/style.css',
    'body{font-family:serif;line-height:1.5}h1,h2{text-align:center}img{max-width:100%}pre{white-space:pre-wrap}table{max-width:100%}',
  );
  final manifest = <XmlNode>[
    element('item', {
      'id': 'nav',
      'href': 'nav.xhtml',
      'media-type': 'application/xhtml+xml',
      'properties': 'nav',
    }),
    element('item', {
      'id': 'style',
      'href': 'style.css',
      'media-type': 'text/css',
    }),
    element('item', {
      'id': 'title',
      'href': 'title.xhtml',
      'media-type': 'application/xhtml+xml',
    }),
  ];
  final spine = <XmlNode>[];
  final cover = book.cover;
  if (cover != null && cover.isNotEmpty) {
    final png =
        cover.length >= 8 &&
        cover[0] == 137 &&
        cover[1] == 80 &&
        cover[2] == 78 &&
        cover[3] == 71;
    final jpg =
        cover.length >= 3 &&
        cover[0] == 255 &&
        cover[1] == 216 &&
        cover[2] == 255;
    if (!png && !jpg) throw ArgumentError('Cover must be a PNG or JPEG image.');
    final name = png ? 'cover.png' : 'cover.jpg';
    archive.addFile(ArchiveFile('EPUB/$name', cover.length, cover));
    manifest.add(
      element('item', {
        'id': 'cover-image',
        'href': name,
        'media-type': png ? 'image/png' : 'image/jpeg',
        'properties': 'cover-image',
      }),
    );
    manifest.add(
      element('item', {
        'id': 'cover',
        'href': 'cover.xhtml',
        'media-type': 'application/xhtml+xml',
      }),
    );
    add(
      'EPUB/cover.xhtml',
      xhtml('Cover', [
        element('div', {}, [
          element('img', {'src': name, 'alt': 'Cover of ${book.title}'}),
        ]),
      ]),
    );
    spine.add(element('itemref', {'idref': 'cover'}));
  }
  add(
    'EPUB/title.xhtml',
    xhtml(book.title, [
      textElement('h1', book.title),
      textElement('p', book.author),
    ]),
  );
  spine.add(element('itemref', {'idref': 'title'}));
  final links = <XmlNode>[];
  for (var i = 0; i < book.chapters.length; i++) {
    final chapter = book.chapters[i];
    final id = 'chapter${(i + 1).toString().padLeft(5, '0')}';
    add(
      'EPUB/$id.xhtml',
      xhtml(chapter.title, [
        textElement('h1', chapter.title),
        ...chapterNodes(chapter.content, chapter.url),
      ]),
    );
    manifest.add(
      element('item', {
        'id': id,
        'href': '$id.xhtml',
        'media-type': 'application/xhtml+xml',
      }),
    );
    spine.add(element('itemref', {'idref': id}));
    links.add(
      element('li', {}, [
        element('a', {'href': '$id.xhtml'}, [XmlText(chapter.title)]),
      ]),
    );
  }
  add(
    'EPUB/nav.xhtml',
    xhtml('Contents', [
      element(
        'nav',
        {'epub:type': 'toc', 'id': 'toc'},
        [textElement('h1', 'Contents'), element('ol', {}, links)],
      ),
    ]),
  );
  final modified = DateTime.now().toUtc().toIso8601String().split('.').first;
  add(
    'EPUB/content.opf',
    document(
      element(
        'package',
        {
          'xmlns': 'http://www.idpf.org/2007/opf',
          'version': '3.0',
          'unique-identifier': 'book-id',
        },
        [
          element(
            'metadata',
            {'xmlns:dc': 'http://purl.org/dc/elements/1.1/'},
            [
              element(
                'dc:identifier',
                {'id': 'book-id'},
                [XmlText(book.chapters.first.url.toString())],
              ),
              textElement('dc:title', book.title),
              textElement('dc:creator', book.author),
              textElement('dc:language', 'en'),
              element(
                'meta',
                {'property': 'dcterms:modified'},
                [XmlText('${modified}Z')],
              ),
            ],
          ),
          element('manifest', {}, manifest),
          element('spine', {}, spine),
        ],
      ),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
