from io import BytesIO
from zipfile import ZipFile

import pytest
from bs4 import BeautifulSoup

from extractors.base import ExtractionError
from extractors.registry import get_extractor
from extractors.royalRoad import RoyalRoadExtractor
from models.chapter import Chapter
from services.extraction import ExtractionService
from services.epub_builder import EpubBuilder


def soup(html):
    return BeautifulSoup(html, 'html.parser')


@pytest.mark.parametrize('url', ['https://evil.test/royalroad.com', 'https://royalroad.com.evil.test', 'https://evil.test/?url=royalroad.com', 'ftp://royalroad.com'])
def test_registry_rejects_host_spoofing(url):
    with pytest.raises(ValueError):
        get_extractor(url)


def test_royalroad_navigation_and_title():
    extractor = RoyalRoadExtractor()
    chapter = extractor.parse_chapter(soup('<h1>Actual title</h1><div class="chapter-content"><p>Text</p></div><a href="/fiction/1/chapter/2">Next Chapter</a>'), 'https://www.royalroad.com/fiction/1/chapter/1', 1)
    assert chapter.title == 'Actual title'
    assert chapter.next_url == 'https://www.royalroad.com/fiction/1/chapter/2'
    final = extractor.parse_chapter(soup('<div class="chapter-content">Text</div><a href="/fiction/1/chapter/1">Previous Chapter</a>'), chapter.next_url, 2)
    assert final.next_url is None


def test_missing_content_fails():
    with pytest.raises(ExtractionError):
        RoyalRoadExtractor().parse_chapter(soup('<h1>Blocked</h1>'), 'https://royalroad.com', 1)


def test_metadata_without_structured_data():
    metadata = RoyalRoadExtractor().parse_book(soup('<h1>Book</h1><table id="chapters"><tbody><tr><td><a href="/fiction/1/chapter/2">First</a></td></tr></tbody></table>'), 'https://royalroad.com/fiction/1')
    assert metadata['chapter_1'] == 'https://royalroad.com/fiction/1/chapter/2'
    assert metadata['author'] is None


def test_loop_detection():
    class Loop(RoyalRoadExtractor):
        def get_chapter(self, url, count):
            return Chapter('Title', '<p>Text</p>', url + '#top')
    with pytest.raises(ExtractionError, match='loop'):
        ExtractionService(lambda url: Loop()).extract_book('https://royalroad.com', 'Book', 'Author', 'https://royalroad.com/chapter/1', b'')


def test_epub_duplicate_titles_and_escaping():
    builder = EpubBuilder('A & B', '<Author>')
    builder.add_chapter('Same / title', '<p>One</p>', 1)
    builder.add_chapter('Same / title', '<p>Two</p>', 2)
    with ZipFile(BytesIO(builder.finalize())) as archive:
        names = archive.namelist()
        assert 'EPUB/chapter-00001.xhtml' in names
        assert 'EPUB/chapter-00002.xhtml' in names
        assert b'A &amp; B' in archive.read('EPUB/title.xhtml')
