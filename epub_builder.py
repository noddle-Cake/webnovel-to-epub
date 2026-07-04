import uuid
from ebooklib import epub

class EpubBuilder:
    def __init__(self, title: str, author: str, cover_bytes: bytes or None = None):
        self.book = epub.EpubBook()
        self.book.set_title(title)
        self.book.set_language("en")
        self.book.add_author(author)

        if cover_bytes:
            self.book.set_cover("cover.jpg", cover_bytes)

        title_page_html = f'''<html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Title Page</title></head>
        <body><h1>{title}</h1><h2>by {author}</h2></body>
        </html>'''
        title_page = epub.EpubHtml(title="Title Page", file_name="title.xhtml", lang="en")
        title_page.content = title_page_html
        self.book.add_item(title_page)
        self.book.spine.append(title_page)

    def add_chapter(self, title: str, html: str, count: int):
        chapter = epub.EpubHtml(title=title, file_name=f"{title}.xhtml", lang="en")
        chapter.content = f"<h1>{title}</h1>\n{html}"
        self.book.add_item(chapter)
        self.book.spine.append(chapter)
        self.book.toc.append(
            epub.Link(f"{title}.xhtml", f"Chapter {count}: {title}", uid=str(uuid.uuid4()))
        )

    def finalize(self) -> bytes:
        css = epub.EpubItem(uid="style", file_name="style.css",
                             content="h1 { text-align: center; }", media_type="text/css")
        self.book.add_item(css)
        self.book.add_item(epub.EpubNcx())
        self.book.add_item(epub.EpubNav())

        tmp_path = f"/tmp/{uuid.uuid4()}.epub"
        epub.write_epub(tmp_path, self.book, {})
        with open(tmp_path, "rb") as f:
            return f.read()