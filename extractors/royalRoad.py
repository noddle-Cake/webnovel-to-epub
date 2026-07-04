import re
import requests
from bs4 import BeautifulSoup
from .base import BaseExtractor, Chapter

class RoyalRoadExtractor(BaseExtractor):
    domain_pattern = r"royalroad\.com"

    def get_chapter(self, url: str, count: int) -> Chapter:
        response = requests.get(url)
        if response.status_code != 200:
            raise RuntimeError(f"Failed to fetch {url}: status {response.status_code}")

        soup = BeautifulSoup(response.content, "html.parser")
        links = soup.find_all("a", class_="btn btn-primary col-xs-4")
        content = soup.find_all("div", class_="chapter-inner chapter-content")

        title = self._title_from_url(url, count)
        html = "\n".join(str(div) for div in content)

        next_url = None
        if not (len(links) != 3 and count > 1):
            next_url = "https://www.royalroad.com" + links[-1]["href"]

        return Chapter(title=title, html=html, next_url=next_url)

    @staticmethod
    def _title_from_url(url: str, count: int) -> str:
        slug = re.search(r'[^/]+$', url).group(0).strip()
        match = re.search(r'^[^-]*-[^-]*-(.*)', slug)
        if match is None:
            return f"Chapter {count}"

        cleaned = list(re.sub(r'-', ' ', match.group(1)))
        cleaned[0] = cleaned[0].upper()
        for i in range(1, len(cleaned)):
            if cleaned[i - 1] == ' ':
                cleaned[i] = cleaned[i].upper()
        return ''.join(cleaned)