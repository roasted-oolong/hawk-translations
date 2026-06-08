import { Controller } from "@hotwired/stimulus"

export default class ChapterReviewController extends Controller<HTMLElement> {
  static values = {
    approveUrl: String,
    saveUrl: String,
  }

  static targets = [
    "chapterCard",
    "editableText",
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
    "savedIndicator",
    "summaryBadge",
    "approveAllForm",
    "approveAllBtn",
  ]

  declare approveUrlValue: string
  declare saveUrlValue: string
  declare chapterCardTargets: HTMLElement[]
  declare editableTextTargets: HTMLTextAreaElement[]
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
  declare savedIndicatorTarget: HTMLElement
  declare summaryBadgeTargets: HTMLElement[]
  declare approveAllFormTarget: HTMLFormElement
  declare approveAllBtnTarget: HTMLButtonElement

  private index = 0
  private approved = new Set<string>()
  private skipped = new Set<string>()

  private handleKeydown = (event: KeyboardEvent) => {
    if ((event.ctrlKey || event.metaKey) && event.key === 's') {
      event.preventDefault()
      this.saveCurrentText()
      return
    }

    const tag = (event.target as HTMLElement).tagName
    if (tag === 'TEXTAREA' || tag === 'INPUT' || tag === 'SELECT') return

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
    }
  }

  connect() {
    this.index = 0
    this.approved = new Set()
    this.skipped = new Set()
    this.renderCurrent()
    this.resizeCurrentTextarea()
    document.addEventListener('keydown', this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown)
  }

  private get total(): number {
    return this.chapterCardTargets.length
  }

  private get currentCard(): HTMLElement {
    return this.chapterCardTargets[this.index]
  }

  private get currentChapterId(): string {
    return this.currentCard.dataset.chapterId ?? ""
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.renderCurrent()
      this.resizeCurrentTextarea()
    }
  }

  approve() {
    const id = this.currentChapterId
    this.saveCurrentText()
    this.approved.add(id)
    this.skipped.delete(id)

    if (this.index >= this.total - 1) {
      this.showSummary()
    } else {
      this.index++
      this.renderCurrent()
      this.resizeCurrentTextarea()
    }
  }

  skip() {
    const id = this.currentChapterId
    this.skipped.add(id)
    this.approved.delete(id)

    if (this.index >= this.total - 1) {
      this.showSummary()
    } else {
      this.index++
      this.renderCurrent()
      this.resizeCurrentTextarea()
    }
  }

  jumpTo({ params: { index } }: { params: { index: number } }) {
    if (index >= 0 && index < this.total) {
      this.index = index
      this.renderCurrent()
      this.resizeCurrentTextarea()
    }
  }

  autoResize(event: Event) {
    const textarea = event.target as HTMLTextAreaElement
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
  }

  private resizeCurrentTextarea() {
    const textarea = this.editableTextTargets[this.index]
    if (!textarea) return
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
  }

  saveCurrentText() {
    const textarea = this.editableTextTargets[this.index]
    if (!textarea) return
    const id = this.currentChapterId
    const url = this.saveUrlValue.replace(":id", id)
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ text: textarea.value }),
    }).then(() => this.flashSaved())
  }

  backToSlideshow() {
    this.summaryScreenTarget.hidden = true
    this.slideshowScreenTarget.hidden = false
    this.footerTarget.hidden = false
    this.renderCurrent()
  }

  onApproveAllSubmit(event: Event) {
    event.preventDefault()
    const form = this.approveAllFormTarget
    form.querySelectorAll("input[name='chapter_ids[]']").forEach(el => el.remove())
    this.approved.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "chapter_ids[]"
      input.value = id
      form.appendChild(input)
    })
    form.submit()
  }

  private renderCurrent() {
    this.chapterCardTargets.forEach((card, i) => {
      card.hidden = i !== this.index
    })

    this.prevBtnTarget.disabled = this.index === 0

    const isLast = this.index >= this.total - 1
    this.approveBtnTarget.textContent = isLast ? "Finish Review" : "Continue"

    const card = this.currentCard
    const num = card.dataset.chapterNumber ?? ""
    const title = card.dataset.chapterTitle ?? ""
    this.topbarTitleTarget.textContent = title
      ? `Chapter ${num} — ${title}`
      : `Chapter ${num}`

    this.counterTextTarget.textContent = `Chapter ${this.index + 1} of ${this.total}`

    this.renderProgress()
  }

  private renderProgress() {
    const done = this.approved.size + this.skipped.size
    const pct = this.total > 0 ? (done / this.total) * 100 : 0
    this.progressFillTarget.style.width = `${pct}%`
    this.progressTextTarget.textContent = `${done} / ${this.total}`

    this.navItemTargets.forEach((item, i) => {
      const card = this.chapterCardTargets[i]
      const cardId = card?.dataset.chapterId ?? ""
      item.classList.remove(
        "chapter-review__nav-item--active",
        "chapter-review__nav-item--approved",
        "chapter-review__nav-item--skipped",
      )
      if (i === this.index) {
        item.classList.add("chapter-review__nav-item--active")
      } else if (this.approved.has(cardId)) {
        item.classList.add("chapter-review__nav-item--approved")
      } else if (this.skipped.has(cardId)) {
        item.classList.add("chapter-review__nav-item--skipped")
      }

      const statusEl = this.navStatusTargets[i]
      if (statusEl) {
        if (this.approved.has(cardId)) {
          statusEl.textContent = "Approved"
        } else if (this.skipped.has(cardId)) {
          statusEl.textContent = "Skipped"
        } else {
          statusEl.textContent = ""
        }
      }
    })
  }

  private showSummary() {
    this.slideshowScreenTarget.hidden = true
    this.footerTarget.hidden = true
    this.summaryScreenTarget.hidden = false
    this.counterTextTarget.textContent = "Review complete"

    this.summaryBadgeTargets.forEach(badge => {
      const id = badge.dataset.chapterId ?? ""
      badge.classList.remove(
        "chapter-review__summary-badge--approved",
        "chapter-review__summary-badge--skipped",
        "chapter-review__summary-badge--pending",
      )
      if (this.approved.has(id)) {
        badge.textContent = "Approved"
        badge.classList.add("chapter-review__summary-badge--approved")
      } else if (this.skipped.has(id)) {
        badge.textContent = "Skipped"
        badge.classList.add("chapter-review__summary-badge--skipped")
      } else {
        badge.textContent = "Pending"
        badge.classList.add("chapter-review__summary-badge--pending")
      }
    })

    const count = this.approved.size
    this.approveAllBtnTarget.textContent = `Mark ${count} ${count === 1 ? "chapter" : "chapters"} as reviewed`
    this.approveAllBtnTarget.disabled = count === 0
  }

  private flashSaved() {
    this.savedIndicatorTarget.hidden = false
    setTimeout(() => {
      this.savedIndicatorTarget.hidden = true
    }, 2000)
  }

  private csrfToken(): string {
    return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
  }
}
