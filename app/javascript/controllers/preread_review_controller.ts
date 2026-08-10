import { Controller } from "@hotwired/stimulus"

// Per-card immediate persist: approve/skip fire a fetch to
// BibleEntryProposalsController the moment they're clicked (or triggered by
// a keyboard shortcut) — no accumulating decisions client-side for a later
// batch submit (see docs/PREREAD_STAGING_DESIGN.md, Group B7). The card is
// then removed from the DOM, which is also how the (shrinking) card/nav
// list and progress bar stay in sync — no separate approved/skipped Set to
// reconcile against a fixed total. Reaching zero remaining cards redirects
// to the novel page; there's no summary/tally screen to land on instead,
// since nothing is left to summarize that isn't already reflected by the
// live bible tables and the dismissed-keys list.
export default class PrereadReviewController extends Controller<HTMLElement> {
  static targets = [
    "entryCard",
    "navItem",
    "slideshowScreen",
    "footer",
    "prevBtn",
    "approveBtn",
    "progressFill",
    "progressText",
    "counterText",
    "topbarTitle",
    "savedIndicator",
    "viewPanel",
    "editPanel",
  ]

  static values = {
    novelUrl: String,
    approveUrl: String,
    skipUrl: String,
    updateUrl: String,
  }

  declare entryCardTargets: HTMLElement[]
  declare navItemTargets: HTMLElement[]
  declare slideshowScreenTarget: HTMLElement
  declare footerTarget: HTMLElement
  declare prevBtnTarget: HTMLButtonElement
  declare approveBtnTarget: HTMLButtonElement
  declare progressFillTarget: HTMLElement
  declare progressTextTarget: HTMLElement
  declare counterTextTarget: HTMLElement
  declare topbarTitleTarget: HTMLElement
  declare savedIndicatorTarget: HTMLElement
  declare viewPanelTargets: HTMLElement[]
  declare editPanelTargets: HTMLElement[]

  declare novelUrlValue: string
  declare approveUrlValue: string
  declare skipUrlValue: string
  declare updateUrlValue: string

  private index = 0
  private originalTotal = 0

  private handleKeydown = (event: KeyboardEvent) => {
    const editPanel = this.editPanelTargets[this.index]
    const inEditMode = editPanel && !editPanel.hidden

    if (inEditMode) {
      if (event.key === 'Escape') {
        event.preventDefault()
        this.cancelEdit()
      } else if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault()
        this.saveEdit()
      }
      return
    }

    const tag = (event.target as HTMLElement).tagName
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return

    switch (event.key) {
      case 'ArrowLeft':
      case 'p':
      case 'P':
        event.preventDefault()
        this.prev()
        break
      case 'ArrowRight':
      case 'a':
      case 'A':
        event.preventDefault()
        this.approve()
        break
      case 's':
      case 'S':
        event.preventDefault()
        this.skip()
        break
      case 'e':
      case 'E':
        event.preventDefault()
        this.enterEditMode()
        break
    }
  }

  connect() {
    this.index = 0
    this.originalTotal = this.total
    this.renderCurrent()
    document.addEventListener('keydown', this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown)
  }

  private get total(): number {
    return this.entryCardTargets.length
  }

  private get currentCard(): HTMLElement {
    return this.entryCardTargets[this.index]
  }

  prev() {
    this.closeCurrentEditPanel()
    if (this.index > 0) {
      this.index--
      this.renderCurrent()
    }
  }

  approve() {
    this.resolveCurrentCard(id => this.persist(this.approveUrlValue, id))
  }

  skip() {
    this.resolveCurrentCard(id => this.persist(this.skipUrlValue, id))
  }

  skipAll() {
    // Each call resolves whatever is now at this.index (0) — resolving
    // removes that card, shifting the next one into its place — so
    // looping this.total times (re-read each iteration) clears every
    // remaining card without needing to snapshot the list up front.
    while (this.total > 0) {
      this.skip()
    }
  }

  jumpTo(event: Event) {
    this.closeCurrentEditPanel()
    const idx = this.navItemTargets.indexOf(event.currentTarget as HTMLElement)
    if (idx >= 0) {
      this.index = idx
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
    const changedFields: Record<string, string> = {}

    editPanel.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-field]').forEach(field => {
      const key = field.dataset.field!
      const value = field.value.trim()
      changedFields[key] = value
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

    // cultural_phrase has no entry here — its Korean text is the main
    // title now (see preread_categories in the view), not a separate
    // .preread-review__korean subtitle element.
    const koreanKeyMap: Record<string, string> = {
      character: 'korean_name',
      location: 'korean_name',
      terminology: 'korean_term',
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

    const id = card.dataset.proposalId!
    const url = this.updateUrlValue.replace(':id', id)
    fetch(url, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': this.csrfToken(),
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ fields: changedFields }),
    }).then(() => this.flashSaved()).catch(() => {
      // Best-effort, same reasoning as #persist below.
    })
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

  private flashSaved() {
    this.savedIndicatorTarget.hidden = false
    setTimeout(() => {
      this.savedIndicatorTarget.hidden = true
    }, 2000)
  }

  // Removes the current card immediately and fires its persist request in
  // the background rather than waiting on the response — a failed request
  // here isn't destructive (worst case: the suggestion resurfaces on a
  // later preread pass, same as if it were never actioned at all), and
  // this is a solo-dev internal tool with no concurrent-editor conflicts
  // to guard against.
  private resolveCurrentCard(action: (id: string) => void) {
    if (this.total === 0) return
    const card = this.currentCard
    const id = card.dataset.proposalId!
    action(id)

    const navItem = this.navItemTargets[this.index]
    card.remove()
    navItem?.remove()

    if (this.total === 0) {
      window.location.href = this.novelUrlValue
      return
    }

    if (this.index >= this.total) this.index = this.total - 1
    this.renderCurrent()
  }

  private persist(urlTemplate: string, id: string) {
    const url = urlTemplate.replace(':id', id)
    fetch(url, {
      method: 'POST',
      headers: { 'X-CSRF-Token': this.csrfToken(), Accept: 'application/json' },
    }).catch(() => {})
  }

  private csrfToken(): string {
    return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
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
    if (this.total === 0) return

    this.entryCardTargets.forEach((card, i) => {
      card.hidden = i !== this.index
    })

    this.prevBtnTarget.disabled = this.index === 0

    const isLast = this.index >= this.total - 1
    this.approveBtnTarget.textContent = isLast ? "Approve & Finish" : "Approve & Next"

    const card = this.currentCard
    const catLabel = card.dataset.categoryLabel ?? ""
    const displayName = card.dataset.displayName ?? ""
    this.topbarTitleTarget.textContent = `${catLabel} — ${displayName}`
    this.counterTextTarget.textContent = `Entry ${this.index + 1} of ${this.total}`

    this.renderProgress()
  }

  private renderProgress() {
    const done = this.originalTotal - this.total
    const pct = this.originalTotal > 0 ? (done / this.originalTotal) * 100 : 0
    this.progressFillTarget.style.width = `${pct}%`
    this.progressTextTarget.textContent = `${done} / ${this.originalTotal}`

    this.navItemTargets.forEach((item, i) => {
      item.classList.toggle("chapter-review__nav-item--active", i === this.index)
    })
  }
}
