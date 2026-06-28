from ebooklib import epub
from bs4 import BeautifulSoup
import requests
import uuid
import re

url = input("Chapter 1 URL: ")
title = input("Book Title: ")
author = input("Author: ")
cover_url = input("Cover (blank to skip, jpg): ")

count = 1

def slugify(text):
    """Convert to safe filename"""
    return re.sub(r'\W+', '_', text.strip().lower())

def book_start(title, author, cover_url):
    book = epub.EpubBook()
    book.set_identifier(str(uuid.uuid4()))
    book.set_title(title)
    book.set_language('en')
    book.add_author(author)

    if cover_url:
        cover_data = requests.get(cover_url).content
        book.set_cover("cover.jpg", cover_data)

    # Title page
    title_page_html = f'''
    <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Title Page</title></head>
        <body>
            <h1>{title}</h1>
            <h2>by {author}</h2>
        </body>
    </html>
    '''
    title_page = epub.EpubHtml(title="Title Page", file_name="title.xhtml", lang="en")
    title_page.content = title_page_html
    book.add_item(title_page)
    return book, [title_page], []

def get_chapter_html(url, book, spine, toc):
    global count
    response = requests.get(url)
    if response.status_code != 200:
        return None

    soup = BeautifulSoup(response.content, "html.parser")

    links = soup.find_all("a", class_="button _secondary _navigation _next")
    content = soup.find_all("div", class_="resize-font chapter-formatting chapter-font-color chapter-font-family")
    title_tag = soup.find("h1", class_="chapter__title")

    if not title_tag:
        raise ValueError("No title found")

    chapter_title = title_tag.get_text(strip=True)
    filename = f"chapter_{count}_{slugify(chapter_title)}.xhtml"

    chapter = epub.EpubHtml(title=chapter_title, file_name=filename, lang="en")
    chapter.content = f"<h1>{chapter_title}</h1>" + "\n".join(str(div) for div in content)

    book.add_item(chapter)
    spine.append(chapter)
    toc.append(epub.Link(filename, chapter_title, str(uuid.uuid4())))

    print(f"Fetched chapter {count}: {chapter_title}")
    count += 1

    return links[-1]["href"] if links else None

# Initialize
book, spine, toc = book_start(title, author, cover_url)
next_url = url

# Fetch chapters
while next_url:
    try:
        next_url = get_chapter_html(next_url, book, spine, toc)
    except Exception as e:
        print(f"Stopping at chapter {count}: {e}")
        break

# Add style
style = 'h1 { text-align: center; }'
css_item = epub.EpubItem(uid="style", file_name="style.css", content=style, media_type="text/css")
book.add_item(css_item)

# TOC and NAV
book.toc = toc
book.spine = ['nav'] + spine
book.add_item(epub.EpubNcx())
book.add_item(epub.EpubNav())

# Finalize and save
filename_safe = slugify(title)
epub.write_epub(f"{filename_safe}.epub", book)
print("✅ EPUB file created successfully!")