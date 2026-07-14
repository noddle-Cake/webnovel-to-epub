import requests

from extractors.registry import get_extractor
from services.epub_builder import EpubBuilder


class ExtractionService:

    def detect_book(self, url: str) -> dict:
        """
        Retrieve book metadata from supported site.
        """

        extractor = get_extractor(url)

        return extractor.get_book_metadata(url)

    from typing import Optional, Callable

    def extract_book(
            self,
            url: str,
            title: str,
            author: str,
            chapter_url: str,
            cover_bytes: Optional[bytes] = None,
            progress_callback: Optional[Callable] = None,
    ) -> bytes:
        """
        Extract chapters and return EPUB bytes.
        """

        extractor = get_extractor(url)


        # If user didn't upload a cover,
        # download detected cover
        if cover_bytes is None:

            metadata = extractor.get_book_metadata(url)

            cover_url = metadata.get("cover_url")

            if cover_url:
                response = requests.get(cover_url)

                if response.status_code == 200:
                    cover_bytes = response.content


        builder = EpubBuilder(
            title,
            author,
            cover_bytes,
        )


        count = 1
        next_url = chapter_url


        while next_url:

            chapter = extractor.get_chapter(
                next_url,
                count
            )


            builder.add_chapter(
                chapter.title,
                chapter.html,
                count,
            )


            if progress_callback:
                progress_callback(
                    count,
                    chapter.title
                )


            next_url = chapter.next_url
            count += 1


        return builder.finalize()