#!/usr/bin/env python3
"""
ocr_chapter.py
--------------
Transcribes Korean text from one or more photo images, in the order given,
and writes the concatenated text to stdout.

Usage:
    ocr_chapter.py <image_path_1> <image_path_2> ... <image_path_N>

Called by OcrChapterJob whenever a chapter is uploaded as photo scans.
Order is taken from argv order and is never re-sorted — the caller (the
browser drop order, resynced through the upload form) is the sole authority
on page order.

Uses Tesseract OCR (Korean language pack), run inside a pre-built Docker
image (docker/tesseract/, tagged hawk-tesseract:latest) rather than a
system-wide install — this box has no sudo access, and Tesseract's shared
library dependency chain (libcurl, libssl, kerberos/ldap, ...) is far
simpler to manage containerized than vendored on the host.

Switched from PaddleOCR 2026-07-15: PaddleOCR's server detection model
produced unpredictable, sometimes-fabricated garbage on real e-reader
screenshots that couldn't be reliably fixed by tiling or parameter tuning
(the failures didn't correlate with image size, JPEG quality, or text-line
position at crop boundaries — never pinned down a cause). Tesseract handled
the same images cleanly: real content throughout, ordinary character-level
OCR noise instead of fabricated text, and no unexplained failures across
multiple test photos.

Each source photo may be a single page or a two-page spread (e-reader
screenshots showing two facing pages side by side — confirmed this
project's actual photos are uniformly 1920x1200 two-page spreads). Spreads
are detected by aspect ratio and split into left/right halves before OCR:
feeding a full spread to Tesseract interleaves the two columns' reading
order and produces the same kind of garbage PaddleOCR did.

Exit code 0 on success, 1 on failure. On any per-image failure the script
exits immediately without writing partial output to stdout, so the caller
never attaches a half-transcribed chapter.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

SPREAD_ASPECT_RATIO_THRESHOLD = 1.2
TESSERACT_DOCKER_IMAGE = "hawk-tesseract:latest"
TESSERACT_LANG = "kor"
TESSERACT_PSM = "4"


def is_page_spread(image: Image.Image, threshold: float = SPREAD_ASPECT_RATIO_THRESHOLD) -> bool:
    """
    Return True if `image` looks like a two-page spread rather than a
    single page. A single book/manuscript page is portrait-ish (roughly
    0.6-0.8 width:height); a two-page spread is landscape. Confirmed
    empirically: this project's real e-reader screenshots are all exactly
    1920x1200 (ratio 1.60), uniformly spreads.
    """
    width, height = image.size
    return (width / height) > threshold


def split_spread(image: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Split a two-page spread into (left_page, right_page) at the horizontal midpoint."""
    width, height = image.size
    midpoint = width // 2
    left = image.crop((0, 0, midpoint, height))
    right = image.crop((midpoint, 0, width, height))
    return left, right


def run_tesseract(image_path: Path, workdir: Path) -> str:
    """
    Run Tesseract (Korean, PSM 4 — "assume a single column of text of
    variable sizes", appropriate for one already-split page) on one image
    and return its extracted text.

    Korean-only, not kor+eng: tested combining language packs to handle
    occasional English terms (e.g. song/show titles), but it made overall
    accuracy worse — several plain Korean words got misread as English-
    looking noise that weren't misread with kor alone. Occasional garbled
    English terms are a smaller loss than widespread Korean degradation.
    """
    output_base = workdir / image_path.stem
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{workdir}:/data",
            TESSERACT_DOCKER_IMAGE,
            f"/data/{image_path.name}",
            f"/data/{output_base.name}",
            "-l", TESSERACT_LANG,
            "--psm", TESSERACT_PSM,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"tesseract failed on {image_path}: {result.stderr}")

    return output_base.with_suffix(".txt").read_text(encoding="utf-8").strip()


def transcribe_image(path: str, workdir: Path) -> str:
    """
    Transcribe one source photo. Splits into left/right halves first if it
    looks like a two-page spread, OCRs each half (or the single page) via
    Tesseract, and returns the page(s)' text in reading order.
    """
    image = Image.open(path)
    pages = list(split_spread(image)) if is_page_spread(image) else [image]

    texts = []
    for index, page in enumerate(pages):
        page_path = workdir / f"{Path(path).stem}_{index}.png"
        page.save(page_path)
        texts.append(run_tesseract(page_path, workdir))

    return "\n\n".join(texts)


def main() -> None:
    paths = sys.argv[1:]
    if not paths:
        sys.stderr.write("ocr_chapter.py: no image paths given\n")
        sys.exit(1)

    transcriptions = []

    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        for path in paths:
            try:
                transcriptions.append(transcribe_image(path, workdir))
            except Exception as exc:
                sys.stderr.write(f"ocr_chapter.py: failed to transcribe {path!r}: {exc}\n")
                sys.exit(1)

    sys.stdout.buffer.write("\n\n".join(transcriptions).encode("utf-8"))


if __name__ == "__main__":
    main()
