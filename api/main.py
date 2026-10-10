import base64
import binascii
import os
import re
from contextlib import asynccontextmanager
from urllib.parse import quote
from pathlib import Path

import requests
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from api.jobs import JobStore
from extractors.base import ExtractionError
from extractors.registry import get_extractor
from services.extraction import ExtractionService

MAX_COVER_BYTES = 8 * 1024 * 1024


class DetectRequest(BaseModel):
    url: HttpUrl


class ExtractRequest(DetectRequest):
    model_config = ConfigDict(str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=500)
    author: str = Field(min_length=1, max_length=500)
    chapter_url: HttpUrl
    cover_base64: str | None = Field(default=None, max_length=12 * 1024 * 1024)


def create_app(service_factory=ExtractionService):
    @asynccontextmanager
    async def lifespan(app):
        app.state.jobs = JobStore(service_factory)
        yield
        app.state.jobs.close()

    app = FastAPI(title="Novel to EPUB", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[s.strip() for s in os.getenv("CORS_ORIGINS", "").split(",") if s.strip()],
        allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["Content-Type"],
    )

    def validate_site(url):
        try:
            return get_extractor(str(url))
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc

    @app.get("/api/health")
    def health():
        return {"status": "ok"}

    @app.post("/api/books/detect")
    def detect(body: DetectRequest):
        validate_site(body.url)
        try:
            return service_factory().detect_book(str(body.url))
        except (ExtractionError, ValueError) as exc:
            raise HTTPException(422, str(exc)) from exc
        except requests.RequestException as exc:
            raise HTTPException(502, "The novel site could not be reached. Try again shortly.") from exc

    @app.post("/api/jobs", status_code=202)
    def extract(body: ExtractRequest):
        extractor = validate_site(body.url)
        if not extractor.supports(str(body.chapter_url)):
            raise HTTPException(422, "The first chapter must belong to the selected site.")
        cover = None
        if body.cover_base64 is not None:
            try:
                cover = base64.b64decode(body.cover_base64, validate=True)
            except (ValueError, binascii.Error) as exc:
                raise HTTPException(422, "Invalid cover encoding.") from exc
            if len(cover) > MAX_COVER_BYTES:
                raise HTTPException(413, "Cover images must be at most 8 MB.")
            if not (cover.startswith(b'\xff\xd8\xff') or cover.startswith(b'\x89PNG\r\n\x1a\n')):
                raise HTTPException(422, "Choose a JPEG or PNG cover image.")
        try:
            job_id = app.state.jobs.start({
                "url": str(body.url), "title": body.title, "author": body.author,
                "chapter_url": str(body.chapter_url), "cover_bytes": cover,
            })
        except OverflowError as exc:
            raise HTTPException(503, str(exc)) from exc
        return {"id": job_id}

    @app.get("/api/jobs/{job_id}")
    def status(job_id: str):
        try:
            return app.state.jobs.snapshot(job_id)
        except KeyError as exc:
            raise HTTPException(404, "This extraction has expired or could not be found.") from exc

    @app.delete("/api/jobs/{job_id}", status_code=204)
    def cancel(job_id: str):
        try:
            app.state.jobs.cancel_job(job_id)
        except KeyError as exc:
            raise HTTPException(404, "Extraction not found.") from exc
        return Response(status_code=204)

    @app.get("/api/jobs/{job_id}/download")
    def download(job_id: str):
        try:
            title, result = app.state.jobs.download(job_id)
        except KeyError as exc:
            raise HTTPException(404, "This EPUB has expired or could not be found.") from exc
        except ValueError as exc:
            raise HTTPException(409, str(exc)) from exc
        filename = re.sub(r'[\x00-\x1f/\\]', '_', title).strip() or "novel"
        return Response(result, media_type="application/epub+zip", headers={
            "Content-Disposition": f"attachment; filename=novel.epub; filename*=UTF-8''{quote(filename + '.epub', safe='')}",
        })

    web_directory = Path(os.getenv("WEB_BUILD_DIR", str(
        Path(__file__).resolve().parents[1] / "flutter_app" / "build" / "web"
    )))
    if web_directory.is_dir():
        app.mount("/", StaticFiles(directory=web_directory, html=True), name="flutter")
    return app


app = create_app()
