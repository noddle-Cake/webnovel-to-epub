import streamlit as st
from extractors.registry import get_extractor
from epub_builder import EpubBuilder
import requests

st.title("Light Novel Extractor")

url = st.text_input("Fiction homepage URL")

if url:
    if st.session_state.get("metadata_url") != url:
        extractor = get_extractor(url)
        st.session_state.metadata = extractor.get_book_metadata(url)
        st.session_state.metadata_url = url

    metadata = st.session_state.metadata

    # pre-filled if detected, blank if not — either way, editable
    title = st.text_input("Title", value=metadata.get("title") or "")

    cover_url = metadata.get("cover_url")
    cover_file = None
    author = metadata.get("author")

    if author:
        author = st.text_input("Author", value=metadata.get("author") or "")


    if cover_url:
        st.image(cover_url, width=150)
        replace_cover = st.checkbox("Upload a different cover instead")
        if replace_cover:
            cover_file = st.file_uploader("Cover image (jpg)", type=["jpg", "jpeg"])
    else:
        st.caption("No cover detected")
        cover_file = st.file_uploader("Cover image (jpg)", type=["jpg", "jpeg"])

    first_chapter_url = metadata.get("chapter_1")
    if not first_chapter_url:
        first_chapter_url = st.text_input("Chapter 1 URL (couldn't auto-detect)")

    if st.button("Extract", type="primary") and title and author and first_chapter_url:
        extractor = get_extractor(url)

        if cover_file:
            cover_bytes = cover_file.read()
        elif cover_url and not (cover_file):
            cover_bytes = requests.get(cover_url).content
        else:
            cover_bytes = None

        builder = EpubBuilder(title, author, cover_bytes)

        status = st.status("Extracting chapters...", expanded=True)
        count = 1
        next_url = first_chapter_url
        print(next_url)
        while next_url:
            chapter = extractor.get_chapter(next_url, count)
            builder.add_chapter(chapter.title, chapter.html, count)
            status.write(f"Chapter {count}: {chapter.title}")
            next_url = chapter.next_url
            count += 1
        status.update(label="Done", state="complete")

        epub_bytes = builder.finalize()
        st.success(f"Extracted {count - 1} chapters")
        st.download_button("Download EPUB", epub_bytes, f"{title}.epub", mime="application/epub+zip")