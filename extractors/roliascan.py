"""RoliaScan novel pages; image-only manga are deliberately rejected."""
import json
from copy import deepcopy
from urllib.parse import urlsplit

from .base import BaseExtractor, Chapter, ExtractionError


class RoliaScanExtractor(BaseExtractor):
    hosts = ("roliascan.com", "www.roliascan.com")

    @staticmethod
    def _book_data(soup):
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                data = json.loads(script.get_text())
            except (ValueError, TypeError):
                continue
            nodes = data if isinstance(data, list) else [data]
            for node in nodes:
                if not isinstance(node, dict):
                    continue
                for item in node.get("@graph", [node]):
                    if isinstance(item, dict) and item.get("@type") == "Book":
                        return item
        return {}

    def parse_book(self, soup, url):
        data = self._book_data(soup)
        heading = soup.select_one("h1")
        title = heading.get_text(" ", strip=True) if heading else data.get("name")
        first = soup.select_one("a#start-reading-btn[href], a.mobile-start-reading-btn[href]")
        first_url = self.link(url, first.get("href") if first else None)
        if not title or not first_url:
            raise ExtractionError(f"RoliaScan book title or first-chapter link missing at {url}")
        if not self.supports(first_url) or not urlsplit(first_url).path.startswith("/read/"):
            raise ExtractionError(f"Invalid RoliaScan first-chapter URL: {first_url}")
        author = data.get("author")
        if isinstance(author, dict):
            author = author.get("name")
        elif isinstance(author, list):
            author = ", ".join(item.get("name", "") if isinstance(item, dict) else str(item)
                               for item in author) or None
        cover = data.get("image")
        if isinstance(cover, dict):
            cover = cover.get("url")
        elif isinstance(cover, list):
            cover = cover[0] if cover else None
        if not cover:
            image = soup.select_one('meta[property="og:image"]')
            cover = image.get("content") if image else None
        description = soup.select_one("#description-content-tab")
        return {"title": title, "author": author,
                "cover_url": self.link(url, cover), "chapter_1": first_url,
                "description": description.get_text(" ", strip=True) if description else data.get("description")}

    def parse_chapter(self, soup, url, count):
        content = soup.select_one(".reader-text")
        if content is None:
            raise ExtractionError(
                f"RoliaScan novel text missing at {url}; the page may require access, "
                "load dynamically, or contain image-only manga."
            )
        content = deepcopy(content)
        for unwanted in content.select("script, style, iframe, form, .rolia-ad-slot"):
            unwanted.decompose()
        if not content.get_text(strip=True):
            raise ExtractionError(f"RoliaScan novel text is empty at {url}")
        heading = soup.select_one("h1")
        title = heading.get_text(" ", strip=True) if heading else f"Chapter {count}"
        next_link = soup.select_one('a[title="Next Chapter"][href], a[rel~="next"][href]')
        if next_link is None:
            next_link = soup.select_one('a[title^="Next: Chapter"][href]')
        next_url = self.link(url, next_link.get("href") if next_link else None)
        if next_url:
            current_path = urlsplit(url).path.rstrip("/").rsplit("/", 1)[0]
            next_path = urlsplit(next_url).path.rstrip("/").rsplit("/", 1)[0]
            if not self.supports(next_url) or current_path != next_path:
                raise ExtractionError(f"RoliaScan next link leaves this novel: {next_url}")
        return Chapter(title=title, html=content.decode_contents(), next_url=next_url)
