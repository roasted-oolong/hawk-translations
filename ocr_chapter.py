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
    text_detection_model_name="PP-OCRv5_mobile_det": this runs on a
    memory-constrained box that also hosts a local LLM server, and the
    default "server" detection model has been observed to die with no
    traceback (consistent with an OOM-kill) under that memory pressure. The
    mobile detection model is ~20x smaller on disk and trades a modest amount
    of detection accuracy for a much smaller memory footprint.
    """
    return PaddleOCR(
        lang="korean",
        enable_mkldnn=False,
        use_doc_orientation_classify=True,
        use_doc_unwarping=False,
        use_textline_orientation=True,
        text_detection_model_name="PP-OCRv5_mobile_det",
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
