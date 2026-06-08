import { Controller } from "@hotwired/stimulus"

export default class PrereadReviewController extends Controller<HTMLElement> {
  static targets = [
    "entryCard",
    "navItem",
    "navStatus",
    "slideshowScreen",
    "summaryScreen",
    "footer",
    "prevBtn",
    "approveBtn",
    "progressFill",
    "progressText",
    "counterText",
    "topbarTitle",
    "summaryRow",
    "summaryApproved",
    "summarySkipped",
    "summaryPending",
    "importForm",
    "importBtn",
    "viewPanel",
    "editPanel",
  ]

  declare entryCardTargets: HTMLElement[]
  declare navItemTargets: HTMLElement[]
  declare navStatusTargets: HTMLElement[]
  declare slideshowScreenTarget: HTMLElement
  declare summaryScreenTarget: HTMLElement
  declare footerTarget: HTMLElement
  declare prevBtnTarget: HTMLButtonElement
  declare approveBtnTarget: HTMLButtonElement
  declare progressFillTarget: HTMLElement
  declare progressTextTarget: HTMLElement
  declare counterTextTarget: HTMLElement
  declare topbarTitleTarget: HTMLElement
  declare summaryRowTargets: HTMLElement[]
  declare summaryApprovedTargets: HTMLElement[]
  declare summarySkippedTargets: HTMLElement[]
  declare summaryPendingTargets: HTMLElement[]
  declare importFormTarget: HTMLFormElement
  declare importBtnTarget: HTMLButtonElement
  declare viewPanelTargets: HTMLElement[]
  declare editPanelTargets: HTMLElement[]

  private index = 0
  private approved = new Set<string>()
  private skipped = new Set<string>()

  connect() {
    this.index = 0
    this.approved = new Set()
    this.skipped = new Set()
    this.renderCurrent()
  }

  private get total(): number {
    return this.entryCardTargets.length
  }

  private get currentCard(): HTMLElement {
    return this.entryCardTargets[this.index]
  }

  private compositeKey(card: HTMLElement): string {
    return `${card.dataset.category}:${card.dataset.koreanKey}`
  }

  prev() {
    this.closeCurrentEditPanel()
    if (this.index > 0) {
      this.index--
      this.renderCurrent()
    }
  }

  approve() {
    const key = this.compositeKey(this.currentCard)
    this.approved.add(key)
    this.skipped.delete(key)

    if (this.index >= this.total - 1) {
      this.showSummary()
    } else {
      this.index++
      this.renderCurrent()
    }
  }

  skip() {
    const key = this.compositeKey(this.currentCard)
    this.skipped.add(key)
    this.approved.delete(key)

    if (this.index >= this.total - 1) {
      this.showSummary()
    } else {
      this.index++
      this.renderCurrent()
    }
  }

  jumpTo({ params: { index } }: { params: { index: number } }) {
    this.closeCurrentEditPanel()
    if (index >= 0 && index < this.total) {
      this.index = index
      this.renderCurrent()
    }
  }

  enterEditMode() {
    const viewPanel = this.viewPanelTargets[this.index]
    const editPanel = this.editPanelTargets[this.index]
    if (!viewPanel || !editPanel) return
    viewPanel.hidden = true
    editPanel.hidden = false
  }

  saveEdit() {
    const card = this.currentCard
    const editPanel = this.editPanelTargets[this.index]
    const viewPanel = this.viewPanelTargets[this.index]
    if (!card || !editPanel || !viewPanel) return

    const entryData: Record<string, unknown> = JSON.parse(card.dataset.entryJson || '{}')

    editPanel.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-field]').forEach(field => {
      const key = field.dataset.field!
      const value = field.value.trim()
      if (value !== '') {
        entryData[key] = value
      } else {
        delete entryData[key]
      }
    })

    card.dataset.entryJson = JSON.stringify(entryData)

    viewPanel.querySelectorAll<HTMLTableRowElement>('tr').forEach(tr => {
      const td = tr.querySelector<HTMLElement>('[data-field]')
      if (!td) return
      const val = entryData[td.dataset.field!]
      const text = val != null ? String(val) : ''
      td.textContent = text
      tr.hidden = text === ''
    })

    const nameKey = card.dataset.nameKey!
    const newName = entryData[nameKey] != null ? String(entryData[nameKey]) : ''
    const titleEl = viewPanel.querySelector<HTMLElement>('.chapter-review__chapter-title')
    if (titleEl && newName) {
      titleEl.textContent = newName
      card.dataset.displayName = newName
    }

    const koreanKeyMap: Record<string, string> = {
      characters: 'korean_name',
      locations: 'korean_name',
      terminology: 'korean_term',
      cultural_phrases: 'korean_phrase',
    }
    const koreanKey = koreanKeyMap[card.dataset.category!]
    if (koreanKey) {
      const koreanEl = viewPanel.querySelector<HTMLElement>('.preread-review__korean')
      if (koreanEl) {
        const newKorean = entryData[koreanKey] != null ? String(entryData[koreanKey]) : ''
        koreanEl.textContent = newKorean
        koreanEl.hidden = newKorean === ''
      }
    }

    editPanel.hidden = true
    viewPanel.hidden = false
    this.renderCurrent()
  }

  cancelEdit() {
    const card = this.currentCard
    const editPanel = this.editPanelTargets[this.index]
    const viewPanel = this.viewPanelTargets[this.index]
    if (!card || !editPanel || !viewPanel) return

    const entryData: Record<string, unknown> = JSON.parse(card.dataset.entryJson || '{}')
    editPanel.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-field]').forEach(field => {
      field.value = entryData[field.dataset.field!] != null ? String(entryData[field.dataset.field!]) : ''
    })

    editPanel.hidden = true
    viewPanel.hidden = false
  }

  backToSlideshow() {
    this.summaryScreenTarget.hidden = true
    this.slideshowScreenTarget.hidden = false
    this.footerTarget.hidden = false
    this.renderCurrent()
  }

  onImportSubmit(event: Event) {
    event.preventDefault()
    const form = this.importFormTarget
    form.querySelectorAll("input[name='approved_entries']").forEach(el => el.remove())

    const approvedData = Array.from(this.approved).map(compositeKey => {
      const card = this.entryCardTargets.find(c => this.compositeKey(c) === compositeKey)
      if (!card) return null
      return {
        ...JSON.parse(card.dataset.entryJson || '{}'),
        category: card.dataset.category,
      }
    }).filter(Boolean)

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "approved_entries"
    input.value = JSON.stringify(approvedData)
    form.appendChild(input)
    form.submit()
  }

  private closeCurrentEditPanel() {
    const editPanel = this.editPanelTargets[this.index]
    const viewPanel = this.viewPanelTargets[this.index]
    if (editPanel && viewPanel && !editPanel.hidden) {
      editPanel.hidden = true
      viewPanel.hidden = false
    }
  }

  private renderCurrent() {
    this.entryCardTargets.forEach((card, i) => {
      card.hidden = i !== this.index
    })

    this.prevBtnTarget.disabled = this.index === 0

    const card = this.currentCard
    const key = this.compositeKey(card)
    const isLast = this.index >= this.total - 1
    const isApproved = this.approved.has(key)

    if (isApproved) {
      this.approveBtnTarget.textContent = isLast ? "Approved — Finish" : "Approved — Next"
      this.approveBtnTarget.classList.add("btn--approved")
    } else {
      this.approveBtnTarget.textContent = isLast ? "Approve & Finish" : "Approve & Next"
      this.approveBtnTarget.classList.remove("btn--approved")
    }

    const catLabel = card.dataset.categoryLabel ?? ""
    const displayName = card.dataset.displayName ?? ""
    this.topbarTitleTarget.textContent = `${catLabel} — ${displayName}`
    this.counterTextTarget.textContent = `Entry ${this.index + 1} of ${this.total}`

    this.renderProgress()
  }

  private renderProgress() {
    const done = this.approved.size + this.skipped.size
    const pct = this.total > 0 ? (done / this.total) * 100 : 0
    this.progressFillTarget.style.width = `${pct}%`
    this.progressTextTarget.textContent = `${done} / ${this.total}`

    this.navItemTargets.forEach((item, i) => {
      const card = this.entryCardTargets[i]
      const key = card ? this.compositeKey(card) : ""
      item.classList.remove(
        "chapter-review__nav-item--active",
        "chapter-review__nav-item--approved",
        "chapter-review__nav-item--skipped",
      )
      if (i === this.index) {
        item.classList.add("chapter-review__nav-item--active")
      } else if (this.approved.has(key)) {
        item.classList.add("chapter-review__nav-item--approved")
      } else if (this.skipped.has(key)) {
        item.classList.add("chapter-review__nav-item--skipped")
      }

      const statusEl = this.navStatusTargets[i]
      if (statusEl) {
        if (this.approved.has(key))      statusEl.textContent = "Approved"
        else if (this.skipped.has(key)) statusEl.textContent = "Skipped"
        else                             statusEl.textContent = ""
      }
    })
  }

  private showSummary() {
    this.slideshowScreenTarget.hidden = true
    this.footerTarget.hidden = true
    this.summaryScreenTarget.hidden = false
    this.counterTextTarget.textContent = "Review complete"

    this.summaryRowTargets.forEach((row, rowIdx) => {
      const cat = row.dataset.category ?? ""
      const total = parseInt(row.dataset.total ?? "0", 10)

      const approvedCount = Array.from(this.approved).filter(k => k.startsWith(`${cat}:`)).length
      const skippedCount  = Array.from(this.skipped).filter(k => k.startsWith(`${cat}:`)).length
      const pendingCount  = total - approvedCount - skippedCount

      if (this.summaryApprovedTargets[rowIdx]) {
        this.summaryApprovedTargets[rowIdx].textContent = String(approvedCount)
      }
      if (this.summarySkippedTargets[rowIdx]) {
        this.summarySkippedTargets[rowIdx].textContent = String(skippedCount)
      }
      if (this.summaryPendingTargets[rowIdx]) {
        this.summaryPendingTargets[rowIdx].textContent = String(pendingCount)
      }
    })

    const count = this.approved.size
    this.importBtnTarget.textContent = `Import ${count} ${count === 1 ? "entry" : "entries"} to Bible`
    this.importBtnTarget.disabled = count === 0
  }
}
