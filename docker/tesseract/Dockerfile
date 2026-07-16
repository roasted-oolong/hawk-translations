# Tesseract OCR (Korean), used by ocr_chapter.py for photo-scanned chapters.
#
# Built once and reused via `docker run` rather than shelling out to a
# system-wide tesseract install: this box has no sudo access, and
# tesseract-ocr pulls in a long chain of shared library dependencies
# (libcurl, libssl, kerberos/ldap, etc.) that are far simpler to manage
# inside a container than to vendor manually on the host.
#
# Build:
#   docker build -t hawk-tesseract:5.3.4 -t hawk-tesseract:latest docker/tesseract
#
# Packages pulled from the official Ubuntu archive (archive.ubuntu.com /
# security.ubuntu.com), APT-signature-verified on install — not a PPA or
# third-party source.
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-kor && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["tesseract"]
