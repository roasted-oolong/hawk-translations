// controllers/index.ts
// Register all Stimulus controllers here.
//
// Naming convention: filename `foo_bar_controller.ts` → identifier "foo-bar"

import { application } from "./application"

import FlashController from "./flash_controller"
application.register("flash", FlashController)

import PollController from "./poll_controller"
application.register("poll", PollController)

import ComboboxController from "./combobox_controller"
application.register("combobox", ComboboxController)

import ModalController from "./modal_controller"
application.register("modal", ModalController)

import DialogController from "./dialog_controller"
application.register("dialog", DialogController)

import ToastController from "./toast_controller"
application.register("toast", ToastController)

// file-upload: single-file drop zone with filename preview.
//   Used on the novel cover art upload in novels/_form.html.erb.
//   Targets: input, zone, preview, submit
import FileUploadController from "./file_upload_controller"
application.register("file-upload", FileUploadController)

// upload-review: unified chapter upload form.
//   Detects language from file content (Hangul ratio), extracts chapter number
//   from filename, renders a per-file review table with editable number inputs
//   and remove buttons. Mirrors ChapterFileClassifier logic from the server.
//   Targets: input, dropZone, reviewTable, reviewBody, submitButton
import UploadReviewController from "./upload_review_controller"
application.register("upload-review", UploadReviewController)

// tabs: novel show tab strip.
//   Manages active tab state, lazy-loads Turbo Frame panels, persists
//   selection to sessionStorage keyed by novel id.
import TabsController from "./tabs_controller"
application.register("tabs", TabsController)

// form-panel: generic open/close for form <dialog> elements.
//   Used on the novels index "New Novel" quick-create dialog.
//   Targets: dialog
import FormPanelController from "./form_panel_controller"
application.register("form-panel", FormPanelController)

// bulk-translate: Bulk Translate dialog on the chapters tab panel.
//   Opens/closes the native <dialog>, manages chapter checkboxes,
//   derives chapter_start/chapter_end (min/max of selected), updates counter.
import BulkTranslateController from "./bulk_translate_controller"
application.register("bulk-translate", BulkTranslateController)

// chapter-select: row selection in the chapters table.
//   Manages checkboxes, shows/hides the action bar, populates chapter_ids[]
//   into the bulk destroy / download / update forms.
import ChapterSelectController from "./chapter_select_controller"
application.register("chapter-select", ChapterSelectController)

// chapter-viewer: single-chapter content editor on the chapter show page.
//   Handles KO toggle (starts off), Ctrl+S save, auto-resize, and
//   window-level scroll sync to the Korean sticky pane in compare mode.
import ChapterViewerController from "./chapter_viewer_controller"
application.register("chapter-viewer", ChapterViewerController)

// chapter-review: full-page chapter review slideshow.
//   Manages slideshow index, per-chapter approve (fetch PATCH) and skip,
//   progress bar, sidebar nav highlights, and screen transitions (slideshow → summary).
import ChapterReviewController from "./chapter_review_controller"
application.register("chapter-review", ChapterReviewController)

// bible-tabs: simple two-panel tab switcher used on bible index pages
//   to separate active bible entries from dismissed preread entries.
import BibleTabsController from "./bible_tabs_controller"
application.register("bible-tabs", BibleTabsController)

// preread-review: full-page preread bible entry review slideshow.
//   Tracks approve/skip per entry (composite category:korean_key keys),
//   shows per-category summary, batch-imports approved entries via form POST.
import PrereadReviewController from "./preread_review_controller"
application.register("preread-review", PrereadReviewController)

// voice-calibration-review: full-page calibration card review slideshow.
//   Accepts/skips new-pattern and retirement cards, sends PATCH per decision,
//   flashes saved indicator, and shows summary on completion.
import VoiceCalibrationReviewController from "./voice_calibration_review_controller"
application.register("voice-calibration-review", VoiceCalibrationReviewController)

// ai-status: polls /ai_status and updates the sidebar indicator dot.
//   Targets: label
import AiStatusController from "./ai_status_controller"
application.register("ai-status", AiStatusController)

// bible-lookup: TAB-to-lookup shortcut for chapter editing.
//   Intercepts TAB on any textarea inside the mounted element when text is
//   selected, searches the bible API, and shows a positioned popover with
//   matches or "Create as" options.
//   Values: searchUrl, novelId
import BibleLookupController from "./bible_lookup_controller"
application.register("bible-lookup", BibleLookupController)

// photo-upload: "Photo scan (OCR)" chapter upload form.
//   Ordered thumbnail list (add via drop/select order, move up/down, remove),
//   keeps the file input's FileList in sync with on-screen order.
//   Targets: input, dropZone, thumbList, submitButton, numberInput
import PhotoUploadController from "./photo_upload_controller"
application.register("photo-upload", PhotoUploadController)
