// bulk_translate_controller.ts
//
// Manages the Bulk Translate <dialog> on the chapters tab panel.
//
// Responsibilities:
//   - open/close the native <dialog>
//   - toggle all chapter checkboxes via the "Select all" input
//   - track selected chapters, derive chapter_start/chapter_end (min/max),
//     update the counter label, and enable/disable the submit button
//
// HTML contract:
//   data-controller="bulk-translate" on the wrapper div
//   data-bulk-translate-target="dialog"         → the <dialog> element
//   data-bulk-translate-target="selectAll"      → the "Select all" checkbox
//   data-bulk-translate-target="checkbox"       → each chapter checkbox (value = chapter number)
//   data-bulk-translate-target="chapterStart"   → hidden chapter_start input
//   data-bulk-translate-target="chapterEnd"     → hidden chapter_end input
//   data-bulk-translate-target="counter"        → span showing selected count
//   data-bulk-translate-target="submitBtn"      → the submit button

import { Controller } from "@hotwired/stimulus"

export default class BulkTranslateController extends Controller {
  static targets = [
    "dialog", "selectAll", "checkbox",
    "chapterStart", "chapterEnd", "counter", "submitBtn",
  ]

  declare dialogTarget:       HTMLDialogElement
  declare selectAllTarget:    HTMLInputElement
  declare checkboxTargets:    HTMLInputElement[]
  declare chapterStartTarget: HTMLInputElement
  declare chapterEndTarget:   HTMLInputElement
  declare counterTarget:      HTMLElement
  declare submitBtnTarget:    HTMLButtonElement

  open(): void {
    this.dialogTarget.showModal()
  }

  close(): void {
    this.dialogTarget.close()
  }

  toggleAll(): void {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.syncSelection()
  }

  updateSelection(): void {
    this.syncSelection()
  }

  private syncSelection(): void {
    const selected = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => Number(cb.value))

    const count = selected.length
    const total = this.checkboxTargets.length

    this.counterTarget.textContent = String(count)
    this.submitBtnTarget.disabled  = count === 0

    if (count > 0) {
      this.chapterStartTarget.value = String(Math.min(...selected))
      this.chapterEndTarget.value   = String(Math.max(...selected))
    } else {
      this.chapterStartTarget.value = ""
      this.chapterEndTarget.value   = ""
    }

    this.selectAllTarget.checked       = count > 0 && count === total
    this.selectAllTarget.indeterminate = count > 0 && count < total
  }
}
