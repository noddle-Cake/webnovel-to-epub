from dataclasses import dataclass
from typing import Optional


@dataclass
class Chapter:
    title: str
    html: str
    next_url: Optional[str] = None