import re
from .royalRoad import RoyalRoadExtractor

EXTRACTORS = [RoyalRoadExtractor]

def get_extractor(url: str):
    for extractor_cls in EXTRACTORS:
        if re.search(extractor_cls.domain_pattern, url):
            return extractor_cls()
    raise ValueError(f"No extractor found for URL: {url}")