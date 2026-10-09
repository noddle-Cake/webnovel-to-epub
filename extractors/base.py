from abc import ABC, abstractmethod
from urllib.parse import urljoin, urlsplit

import requests
from bs4 import BeautifulSoup

from models.chapter import Chapter
from models.metadata import BookMetadata


class ExtractionError(ValueError):
    """The page does not contain the expected novel data."""


class BaseExtractor(ABC):
    hosts: tuple[str, ...] = ()

    def __init__(self, session=None, timeout: float = 30):
        self.session = session if session is not None else requests.Session()
        self.timeout = timeout

    @classmethod
    def supports(cls, url: str) -> bool:
        parsed = urlsplit(url)
        return parsed.scheme in {"http", "https"} and parsed.hostname in cls.hosts

    def fetch(self, url: str):
        response = self.session.get(url, timeout=self.timeout)
        response.raise_for_status()
        return response

    def get_book_metadata(self, url: str) -> BookMetadata:
        response = self.fetch(url)
        return self.parse_book(BeautifulSoup(response.content, "html.parser"), response.url)

    def get_chapter(self, url: str, count: int) -> Chapter:
        response = self.fetch(url)
        chapter = self.parse_chapter(BeautifulSoup(response.content, "html.parser"), response.url, count)
        if not chapter.html.strip():
            raise ExtractionError(f"No chapter content found at {url}")
        return chapter

    @staticmethod
    def link(url: str, href: str | None) -> str | None:
        if not href or not href.strip() or href.startswith("#"):
            return None
        resolved = urljoin(url, href)
        return resolved if urlsplit(resolved).scheme in {"http", "https"} else None

    @abstractmethod
    def parse_book(self, soup: BeautifulSoup, url: str) -> BookMetadata:
        """Parse metadata without performing network requests."""

    @abstractmethod
    def parse_chapter(self, soup: BeautifulSoup, url: str, count: int) -> Chapter:
        """Parse body and explicit next-chapter navigation."""
