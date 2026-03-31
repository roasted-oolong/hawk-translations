# Hawk Translations — Roadmap Phase 3 Archive

Full milestone detail for Phase 3 (M18.5–M21). Archived after Milestone 21.
Current roadmap: see `docs/ROADMAP.md`.

---

# Phase 4 — Upload Redesign ✅ Complete

Goal: replace the two-panel chapter upload form with a unified, adaptive upload experience
that catches problems before submission and detects file language from content.

---

## Milestone 22 — Unified Chapter Upload
**Status: ✅ Complete**

Replace the two-panel layout (`new.html.erb`: bulk panel + single panel) with a single
unified upload experience. The user selects or drops any number of files. The interface
immediately shows a per-file review table. Language (Korean vs English) is detected from
**file content** on both client and server — filename is never used to infer language.
Chapter number is extracted from the **filename** as a convenience; if unparseable, the
user fills in the number manually before submitting. No status select anywhere on the form.