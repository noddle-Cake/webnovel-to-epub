from ebooklib import epub
from bs4 import BeautifulSoup
import requests
import uuid  # To generate unique identifiers for the TOC items
import re

url = input("Chapter 1 URL: ")

count = 1

def get_chapter_html(url, book):
    response = requests.get(url)
    if response.status_code == 200:
        soup = BeautifulSoup(response.content, "html.parser")
        global count

        links = soup.find_all("a", class_="btn btn-primary col-xs-4")
        content = soup.find_all("div", class_="chapter-inner chapter-content")

        title = title_from_url(url)
        chapter_title = f"<h1> {title} </h1>"
        chapter_html = chapter_title + "\n".join(str(div) for div in content)



        # Create the chapter file
        chapter = epub.EpubHtml(title, file_name=f"{title}.xhtml", lang="en")
        chapter.content = chapter_html
        book.add_item(chapter)

        # Add chapter to spine
        book.spine.append(chapter)

        # Add chapter to TOC with a unique UID
        toc_link = epub.Link(f"{title}.xhtml", f"Chapter {count}: {title}", uid=str(uuid.uuid4()))
        book.toc.append(toc_link)

        # Check if the next chapter exists
        if len(links) != 3 and count > 1:
            return None

        count += 1
        return "https://www.royalroad.com" + links[-1]["href"]
    else:
        print(response.status_code)
        return None

def title_from_url(url):
    title = re.search(r'[^/]+$', url).group(0).strip()
    chapter = re.search(r'^[^-]*-[^-]*-(.*)', title)
    if chapter == None:
        global count
        return f"Chapter {count}"
    chapter_clean = re.sub(r'-', ' ', chapter.group(1))
    chapter_clean = list(chapter_clean)
    chapter_clean[0] = chapter_clean[0].upper()
    for i in range(1, len(chapter_clean)):
        if chapter_clean[i-1] == ' ':
            chapter_clean[i] = chapter_clean[i].upper()
    chapter_clean = ''.join(chapter_clean)
    return chapter_clean


def book_start(title):
    author = input("Author: ")
    cover_url = input("Cover(blank to skip, jpg): ")

    book = epub.EpubBook()
    book.set_title(title)
    book.set_language('en')
    book.add_author(author)

    if cover_url:
        cover_data = requests.get(cover_url).content
        book.set_cover('cover.jpg', cover_data)

    # Add Title Page (first page when opening the book)
    title_page_html = '''<html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <title>Title Page</title>
        </head>
        <body>
            <h1>{}</h1>
            <h2>by {}</h2>
        </body>
    </html>'''.format(title, author)

    # Create the title page
    title_page = epub.EpubHtml(title="Title Page", file_name="title.xhtml", lang="en")
    title_page.content = title_page_html
    book.add_item(title_page)

    # Add title page to spine
    book.spine.append(title_page)

    return book

# Initialize the book and start the process

title = input("Title: ")
book = book_start(title)
next_url = url
while next_url:
    next_url = get_chapter_html(next_url, book)

style = 'h1 { text-align: center;}'
css_item = epub.EpubItem(uid="style", file_name="style.css", content=style, media_type="text/css")
book.add_item(css_item)

# Add EpubNcx and EpubNav only after chapters are added
# EpubNcx and EpubNav files are necessary for the Table of Contents
epub_ncx = epub.EpubNcx()
book.add_item(epub_ncx)

epub_nav = epub.EpubNav()
book.add_item(epub_nav)

# Write the EPUB file
epub.write_epub(f"{title}.epub", book, {})
print("EPUB file created")