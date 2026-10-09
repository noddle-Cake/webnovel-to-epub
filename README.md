# Light Novel Extractor

Convert supported web novels to EPUB while preserving chapter formatting.
Currently supports Royal Road and RoliaScan text novels.

For RoliaScan, paste the novel landing page, for example:
`https://roliascan.com/manga/the-regressor-and-the-blind-saint-novel/`.
The extractor reads the first-chapter button and follows explicit next links;
the dynamically loaded chapter list is not needed. Image-only manga and pages
without accessible novel text raise an error.

## Run

```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m ui.ui_test
```

The NiceGUI interface uses `ExtractionService` for metadata detection and EPUB
creation. `ui_main.py` is the legacy Streamlit interface.

## Add a site

1. Add a module in `extractors/` with a class inheriting `BaseExtractor`.
2. Declare exact supported `hosts`, including `www` if appropriate.
3. Implement `parse_book(soup, url)` and `parse_chapter(soup, url, count)`.
4. Import the class and append it to `EXTRACTORS` in `extractors/registry.py`.
5. Add offline parsing tests with representative HTML, including the final
   chapter and missing content.

`parse_book` returns `BookMetadata` with `title`, `author`, `description`,
`cover_url`, and `chapter_1` (use `None` for unavailable values).
`parse_chapter` returns the shared `models.chapter.Chapter` with a title,
HTML body, and `next_url=None` at the end. Raise `ExtractionError` when the
expected content is missing; do not silently export an empty or blocked page.

Use `self.link(url, href)` to resolve relative links. Select the reading body
and explicit next-chapter navigation, rather than relying on button counts or
URL title guesses. Parsing methods do not fetch pages, so they are easy to test.
The base class handles HTTP status checks, a 30-second timeout, and a reusable
session. A custom session can be injected with `Extractor(session=...)`.

`ExtractionService` checks chapter hosts and detects repeated URLs to prevent
navigation loops. `EpubBuilder` uses numbered chapter filenames so repeated
or path-like titles do not collide.

## Test

```sh
pip install pytest
python -m pytest tests -q
```
