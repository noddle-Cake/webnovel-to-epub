import asyncio

from nicegui import ui, run

from services.extraction import ExtractionService


service = ExtractionService()


metadata = {}
cover_bytes = None
epub_bytes = None

progress_queue = asyncio.Queue()


ui.page_title("Light Novel Extractor")


# =====================================================
# UI
# =====================================================

with ui.column().classes("w-full items-center"):

    ui.label(
        "Light Novel Extractor"
    ).classes(
        "text-3xl font-bold"
    )


    # -----------------------------
    # URL
    # -----------------------------

    with ui.card().classes("w-full max-w-4xl"):

        ui.label("Novel").classes(
            "text-xl"
        )

        with ui.row().classes("w-full"):

            url = ui.input(
                label="Fiction homepage URL"
            ).classes(
                "grow"
            )

            detect_button = ui.button(
                "Detect",
                icon="search"
            )


    # -----------------------------
    # Metadata
    # -----------------------------

    with ui.card().classes("w-full max-w-4xl"):

        ui.label(
            "Book Information"
        ).classes(
            "text-xl"
        )


        title = ui.input(
            label="Title"
        ).classes(
            "w-full"
        )


        author = ui.input(
            label="Author"
        ).classes(
            "w-full"
        )


        chapter1 = ui.input(
            label="Chapter 1 URL"
        ).classes(
            "w-full"
        )


    # -----------------------------
    # Cover
    # -----------------------------

    with ui.card().classes("w-full max-w-4xl"):

        ui.label(
            "Cover"
        ).classes(
            "text-xl"
        )


        cover = ui.image().classes(
            "w-48"
        )

        cover.set_visibility(False)


        upload = ui.upload(
            label="Upload cover",
            auto_upload=True
        )


    # -----------------------------
    # Extraction
    # -----------------------------

    with ui.card().classes("w-full max-w-4xl"):

        extract_button = ui.button(
            "Extract EPUB",
            icon="play_arrow"
        ).props(
            "color=positive"
        )


        log = ui.log(
            max_lines=100
        ).classes(
            "w-full h-72"
        )


    # -----------------------------
    # Finished
    # -----------------------------

    with ui.card().classes("w-full max-w-4xl"):

        status = ui.label()


        download_button = ui.button(
            "Download EPUB",
            icon="download"
        )

        download_button.set_visibility(
            False
        )



# =====================================================
# BACKGROUND -> UI MESSAGE HANDLER
# =====================================================

async def update_log():

    while True:

        message = await progress_queue.get()

        log.push(message)



ui.timer(
    0.1,
    update_log
)



# =====================================================
# CALLBACKS
# =====================================================


def detect_book():

    global metadata


    if not url.value:

        ui.notify(
            "Enter a URL first",
            type="warning"
        )

        return


    try:

        metadata = service.detect_book(
            url.value
        )


        title.value = metadata.get(
            "title",
            ""
        )


        author.value = metadata.get(
            "author",
            ""
        )


        chapter1.value = metadata.get(
            "chapter_1",
            ""
        )


        cover_url = metadata.get(
            "cover_url"
        )


        if cover_url:

            cover.set_source(
                cover_url
            )

            cover.set_visibility(
                True
            )


        ui.notify(
            "Book detected",
            type="positive"
        )


    except Exception as e:

        ui.notify(
            str(e),
            type="negative"
        )



async def upload_cover(e):

    global cover_bytes


    cover_bytes = await e.file.read()


    ui.notify(
        "Cover uploaded",
        type="positive"
    )



def extraction_progress(
        count,
        chapter_title
):

    """
    Called from worker thread.
    Do NOT touch UI here.
    """

    progress_queue.put_nowait(
        f"Chapter {count}: {chapter_title}"
    )



async def extract_book():

    global epub_bytes


    if not title.value:

        ui.notify(
            "Missing title",
            type="warning"
        )

        return


    if not author.value:

        ui.notify(
            "Missing author",
            type="warning"
        )

        return


    if not chapter1.value:

        ui.notify(
            "Missing chapter URL",
            type="warning"
        )

        return



    extract_button.disable()

    log.clear()

    status.set_text(
        "Extracting..."
    )


    try:

        epub_bytes = await run.io_bound(
            service.extract_book,
            url.value,
            title.value,
            author.value,
            chapter1.value,
            cover_bytes,
            extraction_progress
        )


        status.set_text(
            "Extraction complete!"
        )


        download_button.set_visibility(
            True
        )


        ui.notify(
            "EPUB created",
            type="positive"
        )


    except Exception as e:

        ui.notify(
            str(e),
            type="negative"
        )


    finally:

        extract_button.enable()



def download_epub():

    if epub_bytes is None:

        return


    ui.download(
        epub_bytes,
        filename=f"{title.value}.epub"
    )



# =====================================================
# EVENTS
# =====================================================

detect_button.on_click(
    detect_book
)


upload.on_upload(
    upload_cover
)


extract_button.on_click(
    extract_book
)


download_button.on_click(
    download_epub
)



ui.run()