from threading import Event
from time import monotonic, sleep
from zipfile import ZipFile
from io import BytesIO

import pytest
from fastapi.testclient import TestClient

from api.main import create_app
from api.jobs import JobStore
from services.epub_builder import EpubBuilder
from services.extraction import ExtractionCancelled, ExtractionService

URL = 'https://roliascan.com/manga/sample/'
BODY = {'url': URL, 'title': 'Sample & Book', 'author': 'Author',
        'chapter_url': 'https://roliascan.com/read/sample/ch1/'}


class FakeService:
    def detect_book(self, url):
        return {'title': 'Sample', 'author': 'Author', 'cover_url': None,
                'chapter_1': BODY['chapter_url'], 'description': 'Synopsis'}

    def extract_book(self, **kwargs):
        if kwargs['cancel_callback']():
            raise ExtractionCancelled()
        kwargs['progress_callback'](1, 'Opening')
        builder = EpubBuilder(kwargs['title'], kwargs['author'], kwargs['cover_bytes'])
        builder.add_chapter('Opening', '<p>Sample story.</p>', 1)
        return builder.finalize()


def wait_for_job(client, job_id):
    deadline = monotonic() + 3
    while monotonic() < deadline:
        job = client.get(f'/api/jobs/{job_id}').json()
        if job['status'] not in {'queued', 'running'}:
            return job
        sleep(.01)
    pytest.fail('Job did not finish')


def test_detect_extract_progress_and_download():
    with TestClient(create_app(FakeService)) as client:
        assert client.get('/api/health').json() == {'status': 'ok'}
        assert client.post('/api/books/detect', json={'url': URL}).json()['title'] == 'Sample'
        response = client.post('/api/jobs', json=BODY)
        assert response.status_code == 202
        job_id = response.json()['id']
        job = wait_for_job(client, job_id)
        assert job['status'] == 'complete'
        assert job['chapters'] == 1
        download = client.get(f'/api/jobs/{job_id}/download')
        assert download.headers['content-type'] == 'application/epub+zip'
        assert 'Sample%20%26%20Book.epub' in download.headers['content-disposition']
        with ZipFile(BytesIO(download.content)) as archive:
            assert b'Sample story.' in archive.read('EPUB/chapter-00001.xhtml')


@pytest.mark.parametrize('changes', [
    {'url': 'https://evil.test/roliascan.com'}, {'title': '  '},
    {'chapter_url': 'https://evil.test/chapter'}, {'cover_base64': '!'},
    {'cover_base64': 'bm90IGFuIGltYWdl'},
])
def test_invalid_job_inputs(changes):
    with TestClient(create_app(FakeService)) as client:
        assert client.post('/api/jobs', json=BODY | changes).status_code == 422


def test_missing_jobs_and_cors():
    with TestClient(create_app(FakeService)) as client:
        assert client.get('/api/jobs/missing').status_code == 404
        assert client.get('/api/jobs/missing/download').status_code == 404
        assert client.delete('/api/jobs/missing').status_code == 404
        response = client.options('/api/jobs', headers={
            'Origin': 'http://localhost:5173', 'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'Content-Type',
        })
        assert response.headers['access-control-allow-origin'] == 'http://localhost:5173'


def test_worker_failure_is_reported():
    class Failure(FakeService):
        def extract_book(self, **kwargs):
            raise ValueError('Chapter missing')
    with TestClient(create_app(Failure)) as client:
        job_id = client.post('/api/jobs', json=BODY).json()['id']
        job = wait_for_job(client, job_id)
        assert job['status'] == 'failed'
        assert job['error'] == 'Chapter missing'
        assert client.get(f'/api/jobs/{job_id}/download').status_code == 409


def test_cancel_and_capacity():
    started, release = Event(), Event()
    class Blocking(FakeService):
        def extract_book(self, **kwargs):
            started.set()
            assert release.wait(3)
            if kwargs['cancel_callback']():
                raise ExtractionCancelled()
            return b'epub'
    with TestClient(create_app(Blocking)) as client:
        client.app.state.jobs.capacity = 1
        job_id = client.post('/api/jobs', json=BODY).json()['id']
        assert started.wait(3)
        assert client.post('/api/jobs', json=BODY).status_code == 503
        assert client.delete(f'/api/jobs/{job_id}').status_code == 204
        release.set()
        assert wait_for_job(client, job_id)['status'] == 'cancelled'


def test_completed_jobs_expire():
    store = JobStore(FakeService, ttl=0)
    try:
        job_id = store.start({'url': URL, 'title': 'Title', 'author': 'Author',
                              'chapter_url': BODY['chapter_url'], 'cover_bytes': None})
        store.executor.shutdown(wait=True)
        with pytest.raises(KeyError):
            store.snapshot(job_id)
    finally:
        store.close()


def test_extraction_cancels_before_fetching():
    def no_fetch(url):
        pytest.fail('Cancelled job should not fetch pages')
    with pytest.raises(ExtractionCancelled):
        ExtractionService(no_fetch).extract_book(URL, 'Book', 'Author', BODY['chapter_url'], cancel_callback=lambda: True)


def test_png_cover_has_correct_epub_media_type():
    import base64
    # A real 1x1 PNG, so the cover test checks the full request/export path.
    png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHUcAAAAASUVORK5CYII='
    with TestClient(create_app(FakeService)) as client:
        job_id = client.post('/api/jobs', json=BODY | {'cover_base64': png}).json()['id']
        assert wait_for_job(client, job_id)['status'] == 'complete'
        with ZipFile(BytesIO(client.get(f'/api/jobs/{job_id}/download').content)) as archive:
            assert archive.read('EPUB/cover.png') == base64.b64decode(png)
            assert b'image/png' in archive.read('EPUB/content.opf')
