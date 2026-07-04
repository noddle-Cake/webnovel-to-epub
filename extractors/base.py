from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

@dataclass
class Chapter:
    title: str
    html: str
    next_url: Optional[str]  # None when there's no next chapter

class BaseExtractor(ABC):
    domain_pattern: str

    @abstractmethod
    def get_chapter(self, url: str, count: int) -> Chapter:
        """Fetch one chapter's title, HTML content, and the URL of the next chapter."""