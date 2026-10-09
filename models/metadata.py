from typing import TypedDict


class BookMetadata(TypedDict):
    title: str | None
    author: str | None
    cover_url: str | None
    chapter_1: str | None
    description: str | None
