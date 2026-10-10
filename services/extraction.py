from typing import Callable
from urllib.parse import urldefrag

from extractors.base import ExtractionError
from extractors.registry import get_extractor
from services.epub_builder import EpubBuilder


class ExtractionCancelled(Exception):
    """The client cancelled an extraction."""


class ExtractionService:
    def __init__(self, extractor_factory=get_extractor):
        self.extractor_factory = extractor_factory

    def detect_book(self, url: str) -> dict:
        return self.extractor_factory(url).get_book_metadata(url)

    def extract_book(self, url: str, title: str, author: str, chapter_url: str,
                     cover_bytes: bytes | None = None,
                     progress_callback: Callable[[int, str], None] | None = None,
                     cancel_callback: Callable[[], bool] | None = None) -> bytes:
        def check_cancelled():
            if cancel_callback and cancel_callback():
                raise ExtractionCancelled()

        check_cancelled()
        extractor = self.extractor_factory(url)
        if cover_bytes is None:
            cover_url = extractor.get_book_metadata(url).get("cover_url")
            if cover_url:
                cover_bytes = extractor.fetch(cover_url).content
        builder = EpubBuilder(title, author, cover_bytes)
        visited = set()
        next_url = chapter_url
        count = 1
        while next_url:
            check_cancelled()
            next_url = urldefrag(next_url)[0]
            if not extractor.supports(next_url):
                raise ExtractionError(f"Chapter navigation left the supported site: {next_url}")
            if next_url in visited:
                raise ExtractionError(f"Chapter navigation loop at {next_url}")
            visited.add(next_url)
            chapter = extractor.get_chapter(next_url, count)
            check_cancelled()
            builder.add_chapter(chapter.title, chapter.html, count)
            if progress_callback:
                progress_callback(count, chapter.title)
            next_url = chapter.next_url
            count += 1
        check_cancelled()
        return builder.finalize()
