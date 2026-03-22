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

// file-upload: drag-and-drop + click-to-browse file input with filename preview.
//   Targets: input, zone, preview, submit
//   Values: none
//   CSS state: .file-upload--dragging on zone; .file-upload__preview--empty on preview
import FileUploadController from "./file_upload_controller"
application.register("file-upload", FileUploadController)
