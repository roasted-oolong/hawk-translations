// chapter_select_controller.ts
// Row selection for the chapters table.
//
// HTML contract:
//   data-controller="chapter-select"                    wrapper div
//   data-chapter-select-target="selectAll"              header checkbox (toggle all)
//   data-chapter-select-target="checkbox"               each row checkbox (value = chapter ID,
//                                                         data-status = chapter status,
//                                                         data-number = chapter number)
//   data-chapter-select-target="actionBar"              bar shown when any row is selected
//   data-chapter-select-target="counter"                span showing selected count
//   data-chapter-select-target="deleteForm"             bulk-destroy form
//   data-chapter-select-target="downloadForm"           bulk-download form
//   data-chapter-select-target="editForm"               bulk-update (status) form
//   data-chapter-select-target="bulkTranslateForm"      wrapper shown when 2+ preread selected
//   data-chapter-select-target="bulkTranslateStart"     chapter_start hidden input (translate)
//   data-chapter-select-target="bulkTranslateEnd"       chapter_end hidden input (translate)
//   data-chapter-select-target="bulkPrereadForm"        wrapper shown when 2+ untranslated/preread_failed selected
//   data-chapter-select-target="bulkPrereadStart"       chapter_start hidden input (preread)
//   data-chapter-select-target="bulkPrereadEnd"         chapter_end hidden input (preread)

import { Controller } from "@hotwired/stimulus"

export default class ChapterSelectController extends Controller {
  static targets = [
    "selectAll", "checkbox", "actionBar", "counter",
    "deleteForm", "downloadForm", "editForm",
    "bulkTranslateForm", "bulkTranslateStart", "bulkTranslateEnd",
    "bulkPrereadForm", "bulkPrereadStart", "bulkPrereadEnd",
  ]

  declare selectAllTarget:         HTMLInputElement
  declare checkboxTargets:         HTMLInputElement[]
  declare actionBarTarget:         HTMLElement
  declare counterTarget:           HTMLElement
  declare deleteFormTarget:        HTMLFormElement
  declare downloadFormTarget:      HTMLFormElement
  declare editFormTarget:          HTMLFormElement
  declare hasBulkTranslateFormTarget: boolean
  declare bulkTranslateFormTarget: HTMLElement
  declare bulkTranslateStartTarget: HTMLInputElement
  declare bulkTranslateEndTarget:  HTMLInputElement
  declare hasBulkPrereadFormTarget: boolean
  declare bulkPrereadFormTarget:   HTMLElement
  declare bulkPrereadStartTarget:  HTMLInputElement
  declare bulkPrereadEndTarget:    HTMLInputElement

  update(): void {
    this.sync()
  }

  toggleAll(): void {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.sync()
  }

  private sync(): void {
    const ids   = this.selectedIds()
    const count = ids.length
    const total = this.checkboxTargets.length

    this.counterTarget.textContent       = String(count)
    this.actionBarTarget.hidden          = count === 0
    this.selectAllTarget.checked         = count > 0 && count === total
    this.selectAllTarget.indeterminate   = count > 0 && count < total

    this.fillIds(this.deleteFormTarget,   ids)
    this.fillIds(this.downloadFormTarget, ids)
    this.fillIds(this.editFormTarget,     ids)

    this.syncBulkActions()
  }

  private syncBulkActions(): void {
    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const statuses = [...new Set(selected.map(cb => cb.dataset.status))]
    const numbers  = selected.map(cb => Number(cb.dataset.number))
    const sameStatus = selected.length >= 2 && statuses.length === 1

    const status = statuses[0]
    const isTranslatable = sameStatus && status === "preread"
    const isPrereadable  = sameStatus && (status === "untranslated" || status === "preread_failed")

    if (this.hasBulkTranslateFormTarget) {
      this.bulkTranslateFormTarget.hidden = !isTranslatable
      if (isTranslatable) {
        this.bulkTranslateStartTarget.value = String(Math.min(...numbers))
        this.bulkTranslateEndTarget.value   = String(Math.max(...numbers))
      }
    }

    if (this.hasBulkPrereadFormTarget) {
      this.bulkPrereadFormTarget.hidden = !isPrereadable
      if (isPrereadable) {
        this.bulkPrereadStartTarget.value = String(Math.min(...numbers))
        this.bulkPrereadEndTarget.value   = String(Math.max(...numbers))
      }
    }
  }

  private selectedIds(): number[] {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => Number(cb.value))
  }

  private fillIds(form: HTMLFormElement, ids: number[]): void {
    form.querySelectorAll("input[data-bulk-id]").forEach(el => el.remove())
    ids.forEach(id => {
      const input = document.createElement("input")
      input.type            = "hidden"
      input.name            = "chapter_ids[]"
      input.dataset.bulkId  = "1"
      input.value           = String(id)
      form.appendChild(input)
    })
  }
}
