// chapter_select_controller.ts
// Row selection for the chapters table.
//
// HTML contract:
//   data-controller="chapter-select"             wrapper div
//   data-chapter-select-target="selectAll"       header checkbox (toggle all)
//   data-chapter-select-target="checkbox"        each row checkbox (value = chapter ID)
//   data-chapter-select-target="actionBar"       bar shown when any row is selected
//   data-chapter-select-target="counter"         span showing selected count
//   data-chapter-select-target="deleteForm"      bulk-destroy form
//   data-chapter-select-target="downloadForm"    bulk-download form
//   data-chapter-select-target="editForm"        bulk-update (status) form

import { Controller } from "@hotwired/stimulus"

export default class ChapterSelectController extends Controller {
  static targets = [
    "selectAll", "checkbox", "actionBar", "counter",
    "deleteForm", "downloadForm", "editForm",
  ]

  declare selectAllTarget:    HTMLInputElement
  declare checkboxTargets:    HTMLInputElement[]
  declare actionBarTarget:    HTMLElement
  declare counterTarget:      HTMLElement
  declare deleteFormTarget:   HTMLFormElement
  declare downloadFormTarget: HTMLFormElement
  declare editFormTarget:     HTMLFormElement

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
