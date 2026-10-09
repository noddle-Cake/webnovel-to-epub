from .base import BaseExtractor
from .royalRoad import RoyalRoadExtractor
from .roliascan import RoliaScanExtractor

EXTRACTORS: list[type[BaseExtractor]] = [RoyalRoadExtractor, RoliaScanExtractor]


def get_extractor(url: str, **kwargs) -> BaseExtractor:
    for extractor_cls in EXTRACTORS:
        if extractor_cls.supports(url):
            return extractor_cls(**kwargs)
    raise ValueError(f"No extractor found for URL: {url}")
