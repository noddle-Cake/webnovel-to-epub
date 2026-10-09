import json

from .base import BaseExtractor, Chapter, ExtractionError


class RoyalRoadExtractor(BaseExtractor):
    hosts = ("royalroad.com", "www.royalroad.com")

    def parse_book(self, soup, url):
        data = {}
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                candidate = json.loads(script.get_text())
            except (ValueError, TypeError):
                continue
            if isinstance(candidate, dict) and candidate.get("name"):
                data = candidate
                break
        heading = soup.select_one("h1")
        author = soup.select_one('a[href^="/profile/"]')
        first = soup.select_one('#chapters tbody a[href*="/chapter/"]')
        target = data.get("potentialAction", {}).get("target", {})
        first_href = target.get("urlTemplate") if isinstance(target, dict) else target
        title = data.get("name") or (heading.get_text(strip=True) if heading else None)
        if not title:
            raise ExtractionError(f"Book title missing at {url}")
        cover = data.get("thumbnailUrl")
        if isinstance(cover, list):
            cover = cover[0] if cover else None
        return {"title": title, "author": author.get_text(strip=True) if author else None,
                "description": data.get("description"), "cover_url": self.link(url, cover),
                "chapter_1": self.link(url, first_href or (first.get("href") if first else None))}

    def parse_chapter(self, soup, url, count):
        content = soup.select_one(".chapter-content")
        if content is None or not content.get_text(strip=True):
            raise ExtractionError(f"Chapter content missing at {url}")
        heading = soup.select_one("h1")
        next_link = soup.select_one('a[rel~="next"]')
        if next_link is None:
            next_link = next((a for a in soup.select('a[href*="/chapter/"]')
                              if a.get_text(" ", strip=True).casefold() == "next chapter"), None)
        return Chapter(heading.get_text(strip=True) if heading else f"Chapter {count}",
                       str(content), self.link(url, next_link.get("href") if next_link else None))
