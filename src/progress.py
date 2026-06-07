"""
src/progress.py
---------------
Writes job progress (0–100) to a temp file that the Rails PipelineJob
polling thread reads to update progress_pct on the TranslationJob record.

Usage:
    from src.progress import report_progress
    report_progress(50)   # 50% complete

The job ID is read from the HAWK_JOB_ID environment variable. If it is not
set (e.g. running interactively), calls are silently ignored.
"""

import os
from pathlib import Path


def progress_file(job_id: str | int) -> Path:
    return Path(f"/tmp/hawk_job_{job_id}.progress")


def report_progress(pct: int) -> None:
    job_id = os.environ.get("HAWK_JOB_ID")
    if not job_id:
        return
    pct = max(0, min(100, int(pct)))
    progress_file(job_id).write_text(str(pct))
