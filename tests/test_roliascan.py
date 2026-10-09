from io import BytesIO
from types import SimpleNamespace
from zipfile import ZipFile

import pytest
from bs4 import BeautifulSoup

from extractors.base import ExtractionError
from extractors.registry import get_extractor
from extractors.roliascan import RoliaScanExtractor
from services.extraction import ExtractionService

BOOK_URL = 'https://roliascan.com/manga/sample-novel/'
FIRST = 'https://roliascan.com/read/sample-novel/ch1-123/'
SECOND = 'https://roliascan.com/read/sample-novel/ch2-124/'
BOOK = '''<h1>Sample Novel</h1>
<script type="application/ld+json">{"@type":"Book","author":{"name":"Sample Author"},"image":"/cover.jpg","description":"Synopsis"}</script>
<a id="start-reading-btn" href="/read/sample-novel/ch1-123/">Read (2)</a>
<div class="chapter-list">Loading chapters...</div>'''
CHAPTER = '''<h1>Sample Novel Chapter 1</h1>
<div class="reader-text px-4"><p><strong>Opening</strong></p><p>Sample <em>text</em>.</p></div>
<a href="/read/sample-novel/ch2-124/" title="Next Chapter"><svg></svg></a>
<div>Donate</div><div id="login-required-modal" class="hidden">Login Required</div>'''
FINAL = '''<h1>Sample Novel Chapter 2</h1><div class="reader-text"><p>End.</p></div>
<a title="Previous Chapter" href="/read/sample-novel/ch1-123/">Previous</a>
<a href="/manga/sample-novel/">Novel Info</a>'''


def parse(html):
    return BeautifulSoup(html, 'html.parser')


def test_metadata_uses_visible_title_and_first_button():
    metadata = RoliaScanExtractor().parse_book(parse(BOOK), BOOK_URL)
    assert metadata == {'title': 'Sample Novel', 'author': 'Sample Author',
                        'cover_url': 'https://roliascan.com/cover.jpg', 'chapter_1': FIRST,
                        'description': 'Synopsis'}


def test_mobile_button_and_malformed_json():
    html = '<script type="application/ld+json">broken</script><h1>Novel</h1><a class="mobile-start-reading-btn" href="/read/novel/ch1/">Read</a>'
    metadata = RoliaScanExtractor().parse_book(parse(html), BOOK_URL)
    assert metadata['title'] == 'Novel'
    assert metadata['author'] is None


def test_chapter_preserves_formatting_without_page_chrome():
    chapter = RoliaScanExtractor().parse_chapter(parse(CHAPTER), FIRST, 1)
    assert chapter.title == 'Sample Novel Chapter 1'
    assert '<em>text</em>' in chapter.html
    assert 'Donate' not in chapter.html
    assert 'Login Required' not in chapter.html
    assert chapter.next_url == SECOND


def test_final_chapter_has_no_next():
    chapter = RoliaScanExtractor().parse_chapter(parse(FINAL), SECOND, 2)
    assert chapter.next_url is None


@pytest.mark.parametrize('html', ['<div id="reader-media">Images</div>', '<div class="reader-text"> </div>', '<h1>Login Required</h1>'])
def test_missing_or_empty_novel_text_fails(html):
    with pytest.raises(ExtractionError):
        RoliaScanExtractor().parse_chapter(parse(html), FIRST, 1)


def test_alternative_next_link_and_relative_url():
    html = '<div class="reader-text"><p>Text</p></div><a title="Next: Chapter 2" href="../ch2-124/">Next Chapter</a>'
    assert RoliaScanExtractor().parse_chapter(parse(html), FIRST, 1).next_url == SECOND


@pytest.mark.parametrize('next_url', ['https://evil.test/read/sample-novel/ch2/', '/read/other-novel/ch2/'])
def test_next_link_cannot_leave_novel(next_url):
    html = f'<div class="reader-text"><p>Text</p></div><a title="Next Chapter" href="{next_url}">Next</a>'
    with pytest.raises(ExtractionError, match='leaves this novel'):
        RoliaScanExtractor().parse_chapter(parse(html), FIRST, 1)


def test_registry():
    assert isinstance(get_extractor(BOOK_URL), RoliaScanExtractor)
    with pytest.raises(ValueError):
        get_extractor('https://roliascan.com.evil.test/manga/sample/')


def test_fetch_to_epub_integration():
    pages = {BOOK_URL: BOOK, FIRST: CHAPTER, SECOND: FINAL}
    calls = []

    class Session:
        def get(self, url, timeout):
            calls.append((url, timeout))
            return SimpleNamespace(content=pages[url].encode(), url=url, raise_for_status=lambda: None)

    extractor = RoliaScanExtractor(session=Session())
    service = ExtractionService(lambda url: extractor)
    metadata = service.detect_book(BOOK_URL)
    progress = []
    result = service.extract_book(BOOK_URL, metadata['title'], metadata['author'], metadata['chapter_1'],
                                  cover_bytes=b'', progress_callback=lambda count, title: progress.append(count))
    assert progress == [1, 2]
    assert calls == [(BOOK_URL, 30), (FIRST, 30), (SECOND, 30)]
    with ZipFile(BytesIO(result)) as archive:
        assert b'<em>text</em>' in archive.read('EPUB/chapter-00001.xhtml')
        assert b'End.' in archive.read('EPUB/chapter-00002.xhtml')
