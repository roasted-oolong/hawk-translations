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

Uses PaddleOCR (Korean-language model) for detection + recognition — a
dedicated, CPU-only OCR engine rather than a vision LLM. Model files are
downloaded automatically on first use and cached under ~/.paddlex.

Exit code 0 on success, 1 on failure. On any per-image failure the script
exits immediately without writing partial output to stdout, so the caller
never attaches a half-transcribed chapter.
"""

import sys

from paddleocr import PaddleOCR


def make_ocr() -> PaddleOCR:
    """
    Build the OCR pipeline once per script run (model load takes a few
    seconds, so this must not happen per image).

    enable_mkldnn=False: oneDNN CPU acceleration crashes during inference on
    some CPUs with this paddlepaddle build (NotImplementedError converting a
    PIR attribute) — disabled in favor of a small CPU perf hit over a crash.
    use_doc_unwarping=False: page-curvature correction is unneeded overhead
    for flat photos. use_doc_orientation_classify/use_textline_orientation
    stay on since phone photos are sometimes rotated 90/180 degrees.

    Uses the default "server" text detection model, not the lighter "mobile"
    variant: mobile detection produced unusable, near-garbage transcriptions
    on real chapter photos (confirmed 2026-07-15 — see chapter 75/id 79's
    korean_source). It was tried as a memory-saving measure for a box that
    also hosted a permanently-resident local LLM server; that LLM now runs
    on-demand and unloads when idle instead, which removes the standing
    memory pressure this was working around, so the smaller/less-accurate
    model is no longer worth the accuracy cost.
    """
    return PaddleOCR(
        lang="korean",
        enable_mkldnn=False,
        use_doc_orientation_classify=True,
        use_doc_unwarping=False,
        use_textline_orientation=True,
    )


def transcribe_image(ocr: PaddleOCR, path: str) -> str:
    lines = []
    for result in ocr.predict(path):
        lines.extend(result.get("rec_texts") or [])
    return "\n".join(lines)


def main() -> None:
    paths = sys.argv[1:]
    if not paths:
        sys.stderr.write("ocr_chapter.py: no image paths given\n")
        sys.exit(1)

    ocr = make_ocr()
    transcriptions = []

    for path in paths:
        try:
            transcriptions.append(transcribe_image(ocr, path))
        except Exception as exc:
            sys.stderr.write(f"ocr_chapter.py: failed to transcribe {path!r}: {exc}\n")
            sys.exit(1)

    sys.stdout.buffer.write("\n\n".join(transcriptions).encode("utf-8"))


if __name__ == "__main__":
    main()
