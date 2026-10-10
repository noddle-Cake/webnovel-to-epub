"""Bounded, ephemeral extraction jobs for a single API process."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from threading import Event, Lock
from time import monotonic
from uuid import uuid4

from services.extraction import ExtractionService, ExtractionCancelled


@dataclass
class Job:
    id: str
    title: str
    status: str = "queued"
    chapters: int = 0
    chapter_title: str = ""
    error: str | None = None
    result: bytes | None = None
    completed_at: float | None = None
    cancel: Event = field(default_factory=Event)


class JobStore:
    def __init__(self, service_factory=ExtractionService, capacity=16, ttl=3600):
        self.service_factory = service_factory
        self.capacity = capacity
        self.ttl = ttl
        self.jobs: dict[str, Job] = {}
        self.lock = Lock()
        self.executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="extract")

    def _prune(self):
        expired = [key for key, job in self.jobs.items()
                   if job.completed_at is not None and monotonic() - job.completed_at > self.ttl]
        for key in expired:
            del self.jobs[key]

    def start(self, arguments):
        with self.lock:
            self._prune()
            if len(self.jobs) >= self.capacity:
                raise OverflowError("The extraction queue is full. Try again later.")
            job = Job(id=uuid4().hex, title=arguments["title"])
            self.jobs[job.id] = job
        self.executor.submit(self._run, job, arguments)
        return job.id

    def _run(self, job, arguments):
        with self.lock:
            job.status = "running"
        try:
            def progress(count, title):
                with self.lock:
                    job.chapters = count
                    job.chapter_title = title
            result = self.service_factory().extract_book(
                **arguments, progress_callback=progress,
                cancel_callback=job.cancel.is_set,
            )
            with self.lock:
                if job.cancel.is_set():
                    job.status = "cancelled"
                else:
                    job.result = result
                    job.status = "complete"
        except ExtractionCancelled:
            with self.lock:
                job.status = "cancelled"
        except Exception as exc:
            with self.lock:
                job.status = "cancelled" if job.cancel.is_set() else "failed"
                job.error = None if job.cancel.is_set() else str(exc)
        finally:
            with self.lock:
                job.completed_at = monotonic()

    def snapshot(self, job_id):
        with self.lock:
            self._prune()
            job = self.jobs[job_id]
            return {"id": job.id, "title": job.title, "status": job.status,
                    "chapters": job.chapters, "chapter_title": job.chapter_title,
                    "error": job.error}

    def download(self, job_id):
        with self.lock:
            self._prune()
            job = self.jobs[job_id]
            if job.status != "complete":
                raise ValueError("The EPUB is not ready yet.")
            return job.title, job.result

    def cancel_job(self, job_id):
        with self.lock:
            self._prune()
            job = self.jobs[job_id]
            if job.status in {"queued", "running"}:
                job.cancel.set()

    def close(self):
        with self.lock:
            for job in self.jobs.values():
                job.cancel.set()
        self.executor.shutdown(wait=True, cancel_futures=True)
