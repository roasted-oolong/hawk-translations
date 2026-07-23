// chapter_select_controller.ts
// Row selection for the chapters table.
//
// HTML contract:
//   data-controller="chapter-select"                    wrapper div
//   data-chapter-select-target="selectAll"              header checkbox (toggle all)
//   data-chapter-select-target="row"                    each table row (index-matched to checkboxes)
//   data-chapter-select-target="checkbox"               each row checkbox (value = chapter ID,
//                                                         data-status = chapter status,
//                                                         data-number = chapter number,
//                                                         data-cancellable-job-id = job ID when chapter has an active job)
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
//   data-chapter-select-target="cancelJobsWrapper"      wrapper shown when any selected chapter has an active job
//   data-chapter-select-target="cancelJobsForm"         the <form> inside cancelJobsWrapper (job_ids[] injected here)
//
// Row click behaviour:
//   Plain click      — toggle this row; set anchor for future shift-clicks
//   Ctrl/Cmd+click   — same as plain click (toggle, set anchor)
//   Shift+click      — set every row between the anchor and this one to the
//                      anchor's current checked state (extend or shrink selection)
//
// Poll re-sync:
//   When the chapters-table turbo frame refreshes (poll), all checkbox DOM
//   elements are replaced. The turbo:frame-load event bubbles up to this
//   controller's element, triggering sync() to update the counter/action bar.

import { Controller } from "@hotwired/stimulus"

export default class ChapterSelectController extends Controller {
  static targets = [
    "selectAll", "row", "checkbox", "actionBar", "counter",
    "deleteForm", "downloadForm", "editForm",
    "bulkTranslateForm", "bulkTranslateStart", "bulkTranslateEnd",
    "bulkPrereadForm", "bulkPrereadStart", "bulkPrereadEnd",
    "cancelJobsWrapper", "cancelJobsForm",
  ]

  declare selectAllTarget:              HTMLInputElement
  declare rowTargets:                   HTMLElement[]
  declare checkboxTargets:              HTMLInputElement[]
  declare actionBarTarget:              HTMLElement
  declare counterTarget:                HTMLElement
  declare deleteFormTarget:             HTMLFormElement
  declare downloadFormTarget:           HTMLFormElement
  declare editFormTarget:               HTMLFormElement
  declare hasBulkTranslateFormTarget:   boolean
  declare bulkTranslateFormTarget:      HTMLElement
  declare bulkTranslateStartTarget:     HTMLInputElement
  declare bulkTranslateEndTarget:       HTMLInputElement
  declare hasBulkPrereadFormTarget:     boolean
  declare bulkPrereadFormTarget:        HTMLElement
  declare bulkPrereadStartTarget:       HTMLInputElement
  declare bulkPrereadEndTarget:         HTMLInputElement
  declare hasCancelJobsWrapperTarget:   boolean
  declare cancelJobsWrapperTarget:      HTMLElement
  declare hasCancelJobsFormTarget:      boolean
  declare cancelJobsFormTarget:         HTMLFormElement

  private anchorIndex: number | null = null
  private persistedIds: Set<number> = new Set()

  private syncAfterFrame = (): void => {
    this.checkboxTargets.forEach(cb => {
      cb.checked = this.persistedIds.has(Number(cb.value))
    })
    this.sync()
  }

  connect(): void {
    this.element.addEventListener("turbo:frame-load", this.syncAfterFrame)
  }

  disconnect(): void {
    this.element.removeEventListener("turbo:frame-load", this.syncAfterFrame)
  }

  update(event: Event): void {
    const checkbox = event.currentTarget as HTMLInputElement
    const index    = this.checkboxTargets.indexOf(checkbox)
    if (index !== -1) this.anchorIndex = index
    this.sync()
  }

  toggleAll(): void {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.anchorIndex = null
    this.sync()
  }

  rowClick(event: MouseEvent): void {
    if ((event.target as Element).closest("a, button, input, select, textarea, label")) return

    const row   = event.currentTarget as HTMLElement
    const index = this.rowTargets.indexOf(row)
    if (index === -1) return

    const checkbox = this.checkboxTargets[index]
    if (!checkbox) return

    if (event.shiftKey && this.anchorIndex !== null) {
      const lo          = Math.min(this.anchorIndex, index)
      const hi          = Math.max(this.anchorIndex, index)
      const targetState = this.checkboxTargets[this.anchorIndex].checked
      for (let i = lo; i <= hi; i++) {
        this.checkboxTargets[i].checked = targetState
      }
    } else {
      checkbox.checked = !checkbox.checked
      this.anchorIndex = index
    }

    this.sync()
  }

  private sync(): void {
    const ids   = this.selectedIds()
    this.persistedIds = new Set(ids)
    const count = ids.length
    const total = this.checkboxTargets.length

    this.counterTarget.textContent     = String(count)
    this.actionBarTarget.hidden        = count === 0
    this.selectAllTarget.checked       = count > 0 && count === total
    this.selectAllTarget.indeterminate = count > 0 && count < total

    this.checkboxTargets.forEach((cb, i) => {
      this.rowTargets[i]?.classList.toggle("data-table__row--selected", cb.checked)
    })

    this.fillIds(this.deleteFormTarget,   ids)
    this.fillIds(this.downloadFormTarget, ids)
    this.fillIds(this.editFormTarget,     ids)

    this.syncBulkActions()
  }

  private syncBulkActions(): void {
    const selected   = this.checkboxTargets.filter(cb => cb.checked)
    const statuses   = [...new Set(selected.map(cb => cb.dataset.status))]
    const numbers    = selected.map(cb => Number(cb.dataset.number))
    const sameStatus = selected.length >= 2 && statuses.length === 1

    const status         = statuses[0]
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

    if (this.hasCancelJobsWrapperTarget) {
      const jobIds = this.cancellableJobIdsFromSelected()
      this.cancelJobsWrapperTarget.hidden = jobIds.length === 0
      if (jobIds.length > 0 && this.hasCancelJobsFormTarget) {
        this.fillJobIds(this.cancelJobsFormTarget, jobIds)
      }
    }
  }

  private cancellableJobIdsFromSelected(): number[] {
    const ids = this.checkboxTargets
      .filter(cb => cb.checked && cb.dataset.cancellableJobId)
      .map(cb => Number(cb.dataset.cancellableJobId))
    return [...new Set(ids)]
  }

  private fillJobIds(form: HTMLFormElement, jobIds: number[]): void {
    form.querySelectorAll("input[data-bulk-job-id]").forEach(el => el.remove())
    jobIds.forEach(id => {
      const input            = document.createElement("input")
      input.type             = "hidden"
      input.name             = "job_ids[]"
      input.dataset.bulkJobId = "1"
      input.value            = String(id)
      form.appendChild(input)
    })
  }

  private selectedIds(): number[] {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => Number(cb.value))
  }

  private fillIds(form: HTMLFormElement, ids: number[]): void {
    form.querySelectorAll("input[data-bulk-id]").forEach(el => el.remove())
    ids.forEach(id => {
      const input           = document.createElement("input")
      input.type            = "hidden"
      input.name            = "chapter_ids[]"
      input.dataset.bulkId  = "1"
      input.value           = String(id)
      form.appendChild(input)
    })
  }
}
