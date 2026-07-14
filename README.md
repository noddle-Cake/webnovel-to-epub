# Light Novel Extractor

## Running

To run the application:

```bash
python ui/main.py
Adding New Extractors

An extractor is a custom parser designed to extract book information and chapters from a specific website.

Extractors generally use tools such as:

BeautifulSoup (HTML parsing)
Regex (URL/title parsing)
Requests (fetching pages)

Currently supported sites:

Royal Road
How Extractors Work

The extraction process follows this pattern:

User provides the homepage URL of a book.
The extractor detects whether it supports the website.
The extractor retrieves book metadata from the homepage, such as:
Title
Author
Cover image
First chapter URL
The extractor uses the first chapter URL as the starting point.
The extractor repeatedly:
Downloads the current chapter page
Extracts the chapter title
Extracts the chapter HTML/content while preserving formatting
Finds the next chapter URL
This continues until there are no more chapters.
The collected chapters are passed to the EPUB builder.
Creating a New Extractor

To add support for another website:

Create a new file inside:
extractors/

Example:

extractors/
├── base.py
├── registry.py
├── royalRoad.py
└── newSite.py
Create a class that inherits from BaseExtractor.

Example:

from .base import BaseExtractor, Chapter


class NewSiteExtractor(BaseExtractor):

    domain_pattern = r"newsite\.com"


    def get_book_metadata(self, url: str) -> dict:
        # Extract:
        # title
        # author
        # cover
        # chapter 1 URL

        return {
            "title": "",
            "author": "",
            "cover_url": "",
            "chapter_1": ""
        }


    def get_chapter(self, url: str, count: int) -> Chapter:
        # Extract:
        # chapter title
        # chapter HTML
        # next chapter URL

        return Chapter(
            title="",
            html="",
            next_url=""
        )
Add the extractor to:
extractors/registry.py

Example:

from .royalRoad import RoyalRoadExtractor
from .newSite import NewSiteExtractor


EXTRACTORS = [
    RoyalRoadExtractor,
    NewSiteExtractor
]
Extractor Requirements

Every extractor must implement:

get_book_metadata()

Returns:

{
    "title": "Book Name",
    "author": "Author Name",
    "cover_url": "https://...",
    "chapter_1": "https://..."
}
get_chapter()

Returns:

Chapter(
    title="Chapter Title",
    html="<p>Chapter content</p>",
    next_url="https://..."
)

next_url should be None when the book has reached the final chapter.

Royal Road Example

The current Royal Road extractor works by:

Book Homepage
      |
      v
Extract metadata
      |
      v
Find Chapter 1 URL
      |
      v
Chapter 1
      |
      v
Extract content + next chapter URL
      |
      v
Chapter 2
      |
      v
Repeat until finished

The extracted HTML is preserved and passed directly into the EPUB builder.