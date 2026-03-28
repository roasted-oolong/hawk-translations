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
