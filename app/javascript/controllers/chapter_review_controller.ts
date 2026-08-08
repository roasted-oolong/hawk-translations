import { Controller } from "@hotwired/stimulus"

type QaSource = "factcheck" | "editor"
type QaSeverity = "strong" | "advisory"
type QaSuggestionStatus = "pending" | "accepted" | "rejected"
type QaFilter = "all" | "editor" | "factcheck" | "strong"

interface QaSuggestion {
  id: string
  source: QaSource
  quote: string
  issue: string
  suggested_revision: string
  severity: QaSeverity
  korean_context: string | null
  status: QaSuggestionStatus
}

interface QaStatusResponse {
  id: number | null
  status: string
  progress_pct: number | null
  suggestions: QaSuggestion[]
}

export default class ChapterReviewController extends Controller<HTMLElement> {
  static values = {
    approveUrl: String,
    saveUrl: String,
    qaCreateUrl: String,
    qaStatusUrl: String,
    qaSuggestionUrl: String,
    translationJobUrl: String,
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
    "compareBtn",
    "splitPanes",
    "koreanPane",
    "englishPane",
    "paneText",
    "qaBtn",
    "qaRunningIndicator",
    "qaRunningLabel",
    "qaNavigator",
    "qaSummary",
    "qaFilterPill",
    "qaFilterCount",
    "qaPosition",
    "qaAcceptAllBtn",
    "qaPane",
    "qaPaneCompare",
    "qaDetail",
    "qaDetailSource",
    "qaDetailSeverity",
    "qaDetailRewrite",
    "qaDetailReason",
    "qaDetailKoreanWrap",
    "qaDetailKorean",
  ]

  declare approveUrlValue: string
  declare saveUrlValue: string
  declare qaCreateUrlValue: string
  declare qaStatusUrlValue: string
  declare qaSuggestionUrlValue: string
  declare translationJobUrlValue: string
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
  declare compareBtnTarget: HTMLButtonElement
  declare splitPanesTargets: HTMLElement[]
  declare koreanPaneTargets: HTMLElement[]
  declare englishPaneTargets: HTMLElement[]
  declare paneTextTargets: HTMLTextAreaElement[]
  declare qaBtnTarget: HTMLButtonElement
  declare qaRunningIndicatorTarget: HTMLElement
  declare qaRunningLabelTarget: HTMLElement
  declare qaNavigatorTarget: HTMLElement
  declare qaSummaryTarget: HTMLElement
  declare qaFilterPillTargets: HTMLElement[]
  declare qaFilterCountTargets: HTMLElement[]
  declare qaPositionTarget: HTMLElement
  declare qaAcceptAllBtnTarget: HTMLButtonElement
  declare qaPaneTargets: HTMLElement[]
  declare qaPaneCompareTargets: HTMLElement[]
  declare qaDetailTarget: HTMLElement
  declare qaDetailSourceTarget: HTMLElement
  declare qaDetailSeverityTarget: HTMLElement
  declare qaDetailRewriteTarget: HTMLElement
  declare qaDetailReasonTarget: HTMLElement
  declare qaDetailKoreanWrapTarget: HTMLElement
  declare qaDetailKoreanTarget: HTMLElement

  private index = 0
  private compareActive = false
  private approved = new Set<string>()
  private skipped = new Set<string>()
  private scrollHandlers = new Map<HTMLElement, () => void>()
  private lastEnglishScrollTop = 0

  // QA state, keyed by chapter id so switching chapters restores each
  // chapter's own run rather than bleeding one chapter's suggestions into
  // another's pane.
  private qaSuggestionsByChapter = new Map<string, QaSuggestion[]>()
  private qaFilter: QaFilter = "all"
  private qaFocusedId: string | null = null
  private qaPollHandle: number | null = null

  // Job id of the last completed chapter_qa run actually shown to the user,
  // keyed by chapter id. qa_status always returns the *latest* chapter_qa
  // job for a chapter, completed or not, so once one chapter has ever
  // finished a run, "completed" is a permanent answer — without this,
  // runQa() below can't tell "a fresh completed job I haven't shown yet"
  // (from the connect()-poll race) apart from "the same job I already
  // displayed and the reviewer dismissed, or re-translated the chapter
  // since" — and kept re-showing the old result forever instead of ever
  // starting a new run.
  private qaSeenJobId = new Map<string, number>()

  // Chapter ids with a chapter_qa job actually in flight right now (queued
  // or running), server-confirmed. renderQaForCurrentChapter() runs on
  // every suggestion interaction (accept/reject/filter/dismiss), not just
  // job completion, so it needs a way to tell "idle, safe to show the Run
  // Quality Check button" apart from "a fresh run is currently in progress
  // for this chapter" — otherwise reviewing old suggestions while a new
  // check runs in the background would stomp the running indicator back to
  // idle mid-run.
  private qaRunningChapters = new Set<string>()

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
    this.toggleKorean()
    document.addEventListener('keydown', this.handleKeydown)
    this.element.addEventListener('click', this.handleQaPaneClick)
    document.addEventListener('pointerdown', this.handleDocumentPointerDown)
    window.addEventListener('resize', this.handleQaDetailReposition)
    window.addEventListener('scroll', this.handleQaDetailReposition, true)
    // Resume watching (or surface the result of) whatever chapter_qa job is
    // already latest for this chapter server-side — otherwise a page reload
    // mid-run always reverts to the idle "Run Quality Check" button even
    // though the job kept running, and a completed run's suggestions are
    // never shown until something happens to poll for them.
    this.pollQaStatus(this.currentChapterId)
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown)
    this.element.removeEventListener('click', this.handleQaPaneClick)
    document.removeEventListener('pointerdown', this.handleDocumentPointerDown)
    window.removeEventListener('resize', this.handleQaDetailReposition)
    window.removeEventListener('scroll', this.handleQaDetailReposition, true)
    if (this.qaPollHandle !== null) window.clearTimeout(this.qaPollHandle)
    this.detachScrollSync()
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
    this.persistApproval(id)

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
    const screen = this.slideshowScreenTarget
    const scrollTop = screen.scrollTop
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
    screen.scrollTop = scrollTop
  }

  toggleKorean() {
    this.compareActive = !this.compareActive
    this.compareBtnTarget.classList.toggle("chapter-review__compare-btn--active", this.compareActive)
    this.element.classList.toggle("chapter-review--compare", this.compareActive)

    this.chapterCardTargets.forEach((card, i) => {
      card.classList.toggle("chapter-review__chapter-card--compare", this.compareActive)
      const textarea = this.editableTextTargets[i]
      const paneText = this.paneTextTargets[i]
      if (!textarea || !paneText) return

      if (this.compareActive) {
        paneText.value = textarea.value
        paneText.style.height = "auto"
        paneText.style.height = `${paneText.scrollHeight}px`
      } else {
        textarea.value = paneText.value
      }
    })

    if (this.compareActive) {
      this.attachScrollSync()
    } else {
      this.detachScrollSync()
      this.resizeCurrentTextarea()
    }
  }

  autoResizePane(event: Event) {
    const textarea = event.target as HTMLTextAreaElement
    const screen = this.slideshowScreenTarget
    const scrollTop = screen.scrollTop
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
    screen.scrollTop = scrollTop
  }

  private attachScrollSync() {
    const screen = this.slideshowScreenTarget
    this.lastEnglishScrollTop = screen.scrollTop
    const handler = () => this.syncScrollToKorean(this.index)
    screen.addEventListener("scroll", handler)
    this.scrollHandlers.set(screen, handler)
  }

  private detachScrollSync() {
    this.scrollHandlers.forEach((handler, el) => {
      el.removeEventListener("scroll", handler)
    })
    this.scrollHandlers.clear()
  }

  private syncScrollToKorean(index: number) {
    const screen = this.slideshowScreenTarget
    const koPane = this.koreanPaneTargets[index]
    if (!koPane) return
    const delta = screen.scrollTop - this.lastEnglishScrollTop
    this.lastEnglishScrollTop = screen.scrollTop
    koPane.scrollTop += delta
  }

  private resizeCurrentTextarea() {
    if (this.compareActive) {
      const paneText = this.paneTextTargets[this.index]
      if (!paneText) return
      paneText.style.height = "auto"
      paneText.style.height = `${paneText.scrollHeight}px`
      return
    }
    const textarea = this.editableTextTargets[this.index]
    if (!textarea) return
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
  }

  saveCurrentText() {
    const textarea = this.editableTextTargets[this.index]
    if (!textarea) return

    if (this.compareActive) {
      const paneText = this.paneTextTargets[this.index]
      if (paneText) textarea.value = paneText.value
    }

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

  private persistApproval(id: string) {
    const url = this.approveUrlValue.replace(":id", id)
    fetch(url, {
      method: "PATCH",
      headers: { "X-CSRF-Token": this.csrfToken() },
    })
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
    this.renderQaForCurrentChapter()

    if (this.compareActive) {
      this.detachScrollSync()
      this.attachScrollSync()
    }
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

  // ── Chapter QA ─────────────────────────────────────────────────────────
  //
  // Two independent QA passes (factcheck + editor) reviewed as Word-style
  // tracked changes. Accepting a suggestion is just a text substitution fed
  // through the *existing* saveCurrentText() path — there's no separate
  // "commit" action; the suggestion's own pending/accepted/rejected status
  // is the only genuinely new persisted state (see docs/DECISIONS.md's
  // chapter_qa entry). Simplification from the reference UI: the detail
  // panel is docked below the navigator rather than a floating tooltip
  // anchored to the clicked span, and compare-mode + QA together shows the
  // same tracked-changes content in the English pane rather than a fully
  // independent layout — both were judged not worth the extra complexity
  // for a first version.

  private get currentCanonicalText(): string {
    const editableText = this.editableTextTargets[this.index]
    const paneText = this.paneTextTargets[this.index]
    if (this.compareActive) return paneText?.value ?? ""
    return editableText?.value ?? ""
  }

  // Entry point for the "⚡ Run Quality Check" button. Checks server-side
  // state first rather than assuming idle: the button can be visible while
  // a job is still actually in flight (e.g. right after a page reload,
  // before the connect()-time status check below has resolved), and firing
  // a second chapter_qa job on top of a running one would waste an LLM run
  // and leave two jobs racing to write qa_status's "latest" answer.
  runQa() {
    const chapterId = this.currentChapterId
    const url = this.qaStatusUrlValue.replace(":id", chapterId)

    fetch(url, { headers: { Accept: "application/json" } })
      .then(res => res.json())
      .then((data: QaStatusResponse) => {
        if (data.status === "queued" || data.status === "running") {
          const cancelAndRerun = window.confirm(
            "A quality check is already running for this chapter. Cancel it and start a new one?"
          )
          if (cancelAndRerun) {
            this.cancelJob(data.id).then(() => this.startQa(chapterId))
          } else {
            this.pollQaStatus(chapterId)
          }
          return
        }
        // A completed run already sits server-side. If we haven't shown
        // *this specific job* yet (e.g. connect()'s own status check just
        // hasn't resolved before the click), show it instead of silently
        // kicking off a second, redundant paid LLM run. But if this job id
        // was already surfaced once (shown, or shown-then-dismissed) — the
        // reviewer clicking "Run Quality Check" again is a deliberate
        // request for a fresh pass (e.g. after re-translating the chapter),
        // not a request to see the same stale result again.
        if (data.status === "completed") {
          if (data.id !== null && this.qaSeenJobId.get(chapterId) === data.id) {
            this.startQa(chapterId)
          } else {
            this.pollQaStatus(chapterId)
          }
          return
        }
        this.startQa(chapterId)
      })
      .catch(() => this.startQa(chapterId))
  }

  private startQa(chapterId: string) {
    const card = this.currentCard
    const chapterNumber = card.dataset.chapterNumber ?? ""
    this.qaRunningChapters.add(chapterId)
    this.qaBtnTarget.hidden = true
    this.qaRunningIndicatorTarget.hidden = false
    this.qaRunningLabelTarget.textContent = "Running factcheck pass…"

    const body = new URLSearchParams({
      "translation_job[job_type]": "chapter_qa",
      "translation_job[chapter_start]": chapterNumber,
      "translation_job[chapter_end]": chapterNumber,
    }).toString()

    fetch(this.qaCreateUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    })
      .then(() => this.pollQaStatus(chapterId))
      .catch(() => this.resetQaToIdle(chapterId))
  }

  private cancelJob(jobId: number | null): Promise<void> {
    if (jobId === null) return Promise.resolve()
    const url = this.translationJobUrlValue.replace(":id", String(jobId))
    return fetch(url, {
      method: "DELETE",
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
    }).then(() => undefined, () => undefined)
  }

  private pollQaStatus(chapterId: string) {
    // Guards against a stale poll loop writing into the wrong chapter's UI
    // if the reviewer navigates away while a check is still running.
    if (chapterId !== this.currentChapterId) return

    const url = this.qaStatusUrlValue.replace(":id", chapterId)
    fetch(url, { headers: { Accept: "application/json" } })
      .then(res => res.json())
      .then((data: QaStatusResponse) => {
        if (chapterId !== this.currentChapterId) return

        if (data.status === "queued" || data.status === "running") {
          // Set (not just update) visibility every tick — this same method
          // now also runs once from connect() to resume watching a job that
          // was already in flight before the page loaded, when the button
          // is still in its default server-rendered visible state.
          this.qaRunningChapters.add(chapterId)
          this.qaBtnTarget.hidden = true
          this.qaRunningIndicatorTarget.hidden = false
          const pct = data.progress_pct ?? 0
          this.qaRunningLabelTarget.textContent = pct < 50 ? "Running factcheck pass…" : "Running editor pass…"
          this.qaPollHandle = window.setTimeout(() => this.pollQaStatus(chapterId), 2000)
          return
        }

        this.qaRunningChapters.delete(chapterId)

        if (data.status === "completed") {
          this.qaSuggestionsByChapter.set(chapterId, data.suggestions)
          if (data.id !== null) this.qaSeenJobId.set(chapterId, data.id)
          this.qaFilter = "all"
          this.qaFocusedId = this.firstPendingId(data.suggestions)
          this.renderQaForCurrentChapter()
          return
        }

        // failed, cancelled, or none — nothing to review, back to idle.
        this.resetQaToIdle(chapterId)
      })
      .catch(() => this.resetQaToIdle(chapterId))
  }

  private resetQaToIdle(chapterId: string) {
    this.qaRunningChapters.delete(chapterId)
    this.qaRunningIndicatorTarget.hidden = true
    this.qaBtnTarget.hidden = false
  }

  private firstPendingId(suggestions: QaSuggestion[]): string | null {
    return suggestions.find(s => s.status === "pending")?.id ?? null
  }

  private filteredPendingSuggestions(suggestions: QaSuggestion[]): QaSuggestion[] {
    return suggestions.filter(s => {
      if (s.status !== "pending") return false
      if (this.qaFilter === "editor") return s.source === "editor"
      if (this.qaFilter === "factcheck") return s.source === "factcheck"
      if (this.qaFilter === "strong") return s.severity === "strong"
      return true
    })
  }

  private renderQaForCurrentChapter() {
    const chapterId = this.currentChapterId
    const suggestions = this.qaSuggestionsByChapter.get(chapterId)
    const editableText = this.editableTextTargets[this.index]
    const paneText = this.paneTextTargets[this.index]
    const qaPane = this.qaPaneTargets[this.index]
    const qaPaneCompare = this.qaPaneCompareTargets[this.index]

    if (!suggestions || suggestions.length === 0) {
      this.qaNavigatorTarget.hidden = true
      this.closeQaDetail()
      if (qaPane) qaPane.hidden = true
      if (qaPaneCompare) qaPaneCompare.hidden = true
      if (editableText) editableText.hidden = false
      if (paneText) paneText.hidden = false
      if (!this.qaRunningChapters.has(chapterId)) this.resetQaToIdle(chapterId)
      return
    }

    // Button and tracked-changes coexist: a completed run's suggestions stay
    // on screen (and "Run Quality Check" stays clickable, not swapped out
    // for the navigator) so re-checking after a re-translation, or after
    // accepting/rejecting a few suggestions, doesn't require dismissing the
    // current results first. Only suppressed while a fresh run for this
    // chapter is actually in flight — see qaRunningChapters above.
    if (!this.qaRunningChapters.has(chapterId)) {
      this.qaRunningIndicatorTarget.hidden = true
      this.qaBtnTarget.hidden = false
    }
    this.qaNavigatorTarget.hidden = false

    const html = this.buildTrackedChangesHtml(this.textForRendering(chapterId, editableText, paneText), suggestions)
    if (qaPane) { qaPane.innerHTML = html; qaPane.hidden = false }
    if (qaPaneCompare) { qaPaneCompare.innerHTML = html; qaPaneCompare.hidden = false }
    if (editableText) editableText.hidden = true
    if (paneText) paneText.hidden = true

    this.renderQaNavigator(suggestions)
  }

  // Falls back to editableText's value for a chapter that isn't the one
  // currently on screen (shouldn't normally be hit, since qaSuggestionsByChapter
  // is only ever read for the current chapter, but keeps this function total).
  private textForRendering(_chapterId: string, editableText?: HTMLTextAreaElement, paneText?: HTMLTextAreaElement): string {
    if (this.compareActive) return paneText?.value ?? editableText?.value ?? ""
    return editableText?.value ?? paneText?.value ?? ""
  }

  private renderQaNavigator(suggestions: QaSuggestion[]) {
    const pending = suggestions.filter(s => s.status === "pending")
    const accepted = suggestions.filter(s => s.status === "accepted").length
    const rejected = suggestions.filter(s => s.status === "rejected").length

    if (pending.length === 0) {
      this.qaSummaryTarget.textContent = "All resolved"
    } else {
      const decidedSuffix = accepted || rejected ? ` · ${accepted} accepted · ${rejected} rejected` : ""
      this.qaSummaryTarget.textContent = `${pending.length} suggestion${pending.length === 1 ? "" : "s"}${decidedSuffix}`
    }

    const counts: Record<QaFilter, number> = {
      all: pending.length,
      editor: pending.filter(s => s.source === "editor").length,
      factcheck: pending.filter(s => s.source === "factcheck").length,
      strong: pending.filter(s => s.severity === "strong").length,
    }
    this.qaFilterPillTargets.forEach(pill => {
      const filter = (pill.dataset.filter ?? "all") as QaFilter
      pill.classList.toggle("chapter-review__qa-filter-pill--active", filter === this.qaFilter)
    })
    this.qaFilterCountTargets.forEach(el => {
      const filter = (el.dataset.filter ?? "all") as QaFilter
      el.textContent = String(counts[filter])
    })

    const filtered = this.filteredPendingSuggestions(suggestions)
    const focusedIndex = filtered.findIndex(s => s.id === this.qaFocusedId)
    this.qaPositionTarget.textContent = filtered.length > 0 ? `${Math.max(focusedIndex, 0) + 1} / ${filtered.length}` : ""
    this.qaAcceptAllBtnTarget.hidden = pending.length === 0
  }

  setQaFilter({ params: { filter } }: { params: { filter: QaFilter } }) {
    this.closeQaDetail()
    this.qaFilter = filter
    const suggestions = this.qaSuggestionsByChapter.get(this.currentChapterId) ?? []
    const filtered = this.filteredPendingSuggestions(suggestions)
    this.qaFocusedId = filtered[0]?.id ?? null
    this.renderQaForCurrentChapter()
    this.scrollToFocusedSuggestion()
  }

  qaNext() {
    this.stepQaFocus(1)
  }

  qaPrev() {
    this.stepQaFocus(-1)
  }

  private stepQaFocus(delta: number) {
    const suggestions = this.qaSuggestionsByChapter.get(this.currentChapterId) ?? []
    const filtered = this.filteredPendingSuggestions(suggestions)
    if (filtered.length === 0) return
    this.closeQaDetail()
    const currentIndex = filtered.findIndex(s => s.id === this.qaFocusedId)
    const nextIndex = (currentIndex + delta + filtered.length) % filtered.length
    this.qaFocusedId = filtered[nextIndex]?.id ?? null
    this.renderQaForCurrentChapter()
    this.scrollToFocusedSuggestion()
  }

  private scrollToFocusedSuggestion() {
    if (!this.qaFocusedId) return
    requestAnimationFrame(() => {
      this.findVisibleSuggestionAnchor(this.qaFocusedId)?.scrollIntoView({ behavior: "smooth", block: "center" })
    })
  }

  // buildTrackedChangesHtml renders the same suggestion markup into both
  // qaPane (single-column) and qaPaneCompare (split view) — only one of the
  // two is ever actually visible (see the CSS rule hiding non-compare
  // qa-pane while --compare is active), but a blind element-wide
  // querySelector for a suggestion id can still match the hidden copy,
  // which has a zero-size bounding rect and breaks anything measuring it.
  // Scope the lookup to whichever pane is actually on screen right now.
  private findVisibleSuggestionAnchor(id: string | null): HTMLElement | null {
    if (!id) return null
    const pane = this.compareActive ? this.qaPaneCompareTargets[this.index] : this.qaPaneTargets[this.index]
    return pane?.querySelector<HTMLElement>(`[data-suggestion-id="${id}"]`) ?? null
  }

  qaAcceptAll() {
    const chapterId = this.currentChapterId
    const suggestions = this.qaSuggestionsByChapter.get(chapterId)
    if (!suggestions) return
    const pending = suggestions.filter(s => s.status === "pending")
    if (pending.length === 0) return

    const editableText = this.editableTextTargets[this.index]
    const paneText = this.paneTextTargets[this.index]
    const target = this.compareActive ? paneText : editableText
    if (target) {
      let value = target.value
      for (const suggestion of pending) {
        value = value.replace(suggestion.quote, suggestion.suggested_revision)
      }
      target.value = value
      this.saveCurrentText()
    }

    pending.forEach(suggestion => {
      suggestion.status = "accepted"
      this.persistQaDecision(chapterId, suggestion.id, "accepted")
    })
    this.qaFocusedId = null
    this.closeQaDetail()
    this.renderQaForCurrentChapter()
  }

  dismissQa() {
    this.qaSuggestionsByChapter.delete(this.currentChapterId)
    this.closeQaDetail()
    this.renderQaForCurrentChapter()
  }

  private handleQaPaneClick = (event: Event) => {
    const target = (event.target as HTMLElement).closest<HTMLElement>("[data-suggestion-id]")
    if (!target) return
    this.openQaDetail(target.dataset.suggestionId ?? "")
  }

  private openQaDetail(id: string) {
    // Toggle: clicking the already-open suggestion again closes it — mirrors
    // the prototype's onClick={() => onToggleTooltip(isOpen ? null : id)}.
    if (!this.qaDetailTarget.hidden && this.qaFocusedId === id) {
      this.closeQaDetail()
      return
    }

    const suggestions = this.qaSuggestionsByChapter.get(this.currentChapterId) ?? []
    const suggestion = suggestions.find(s => s.id === id)
    if (!suggestion) return

    this.qaFocusedId = id
    this.qaDetailSourceTarget.textContent = suggestion.source === "factcheck" ? "Factcheck" : "Editor"
    this.qaDetailSourceTarget.className = `chapter-review__qa-badge chapter-review__qa-badge--source-${suggestion.source}`
    this.qaDetailSeverityTarget.textContent = suggestion.severity === "strong" ? "⬆ Strong" : "Advisory"
    this.qaDetailSeverityTarget.className = `chapter-review__qa-badge chapter-review__qa-badge--severity-${suggestion.severity}`
    this.qaDetailRewriteTarget.textContent = suggestion.suggested_revision
    this.qaDetailReasonTarget.textContent = suggestion.issue

    if (suggestion.korean_context) {
      this.qaDetailKoreanTarget.textContent = suggestion.korean_context
      this.qaDetailKoreanWrapTarget.hidden = false
    } else {
      this.qaDetailKoreanWrapTarget.hidden = true
    }

    this.qaDetailTarget.hidden = false
    // Rebuilds the tracked-changes markup (adds the --focused highlight to
    // this suggestion's span) — the span the click event actually fired on
    // gets thrown away by that innerHTML rebuild, so positioning has to
    // happen afterward, against the freshly-rendered node.
    this.renderQaForCurrentChapter()
    this.positionQaDetail()
  }

  closeQaDetail() {
    this.qaDetailTarget.hidden = true
  }

  // Anchors the floating detail popup under (or, if too close to the
  // viewport bottom, above) whichever suggestion span is currently focused
  // — ported from the prototype's SuggestionTooltip placement logic.
  private positionQaDetail() {
    const anchor = this.findVisibleSuggestionAnchor(this.qaFocusedId)
    if (!anchor) return

    const detail = this.qaDetailTarget
    const GAP = 8
    const EDGE = 12
    const ar = anchor.getBoundingClientRect()
    const dr = detail.getBoundingClientRect()

    let top = ar.bottom + GAP
    if (top + dr.height + GAP > window.innerHeight) {
      top = ar.top - dr.height - GAP
    }
    top = Math.max(EDGE, top)

    let left = ar.left
    if (left + dr.width > window.innerWidth - EDGE) {
      left = window.innerWidth - dr.width - EDGE
    }
    left = Math.max(EDGE, left)

    detail.style.top = `${top}px`
    detail.style.left = `${left}px`
  }

  // Click-outside dismissal — matches the prototype's document pointerdown
  // listener. Clicks on a suggestion span are excluded so openQaDetail's own
  // toggle/retarget logic (above) stays the single source of truth for what
  // happens when a span is clicked, rather than this handler racing it.
  private handleDocumentPointerDown = (event: PointerEvent) => {
    if (this.qaDetailTarget.hidden) return
    const target = event.target as Node
    if (this.qaDetailTarget.contains(target)) return
    if ((target as HTMLElement).closest?.("[data-suggestion-id]")) return
    this.closeQaDetail()
  }

  // Keeps the floating popup anchored correctly if the window resizes or
  // the chapter text scrolls underneath it while it's open.
  private handleQaDetailReposition = () => {
    if (this.qaDetailTarget.hidden) return
    this.positionQaDetail()
  }

  qaAcceptFocused() {
    if (this.qaFocusedId) this.applyQaDecision(this.qaFocusedId, "accepted")
  }

  qaRejectFocused() {
    if (this.qaFocusedId) this.applyQaDecision(this.qaFocusedId, "rejected")
  }

  private applyQaDecision(id: string, status: "accepted" | "rejected") {
    const chapterId = this.currentChapterId
    const suggestions = this.qaSuggestionsByChapter.get(chapterId)
    if (!suggestions) return
    const suggestion = suggestions.find(s => s.id === id)
    if (!suggestion) return

    if (status === "accepted") {
      const editableText = this.editableTextTargets[this.index]
      const paneText = this.paneTextTargets[this.index]
      const target = this.compareActive ? paneText : editableText
      if (target) {
        target.value = target.value.replace(suggestion.quote, suggestion.suggested_revision)
        this.saveCurrentText()
      }
    }

    suggestion.status = status
    this.persistQaDecision(chapterId, id, status)

    // Deliberately does not auto-focus or scroll to "the next" suggestion —
    // resolving one used to jump the reviewer's screen to whatever the flat
    // suggestions array considered next, which (before chapter_qa.rb ordered
    // it by position) could be anywhere else in the chapter, and even now
    // means yanking the viewport away from wherever the reviewer is actually
    // reading. Scrolling stays reserved for deliberate navigation — qaNext/
    // qaPrev, a filter change, or clicking a span directly.
    this.qaFocusedId = null
    this.closeQaDetail()
    this.renderQaForCurrentChapter()
  }

  private persistQaDecision(chapterId: string, suggestionId: string, status: "accepted" | "rejected") {
    const url = this.qaSuggestionUrlValue
      .replace(":id", chapterId)
      .replace(":suggestionId", suggestionId)
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ status }),
    })
  }

  private buildTrackedChangesHtml(text: string, suggestions: QaSuggestion[]): string {
    interface Span { start: number; end: number; suggestion: QaSuggestion }
    const spans: Span[] = []

    for (const suggestion of suggestions) {
      if (suggestion.status === "rejected") continue
      const idx = text.indexOf(suggestion.quote)
      if (idx === -1) continue // quote no longer present (e.g. a concurrent hand-edit) — known limitation, skip silently
      const overlaps = spans.some(sp => idx < sp.end && idx + suggestion.quote.length > sp.start)
      if (overlaps) continue
      spans.push({ start: idx, end: idx + suggestion.quote.length, suggestion })
    }
    spans.sort((a, b) => a.start - b.start)

    let html = ""
    let cursor = 0
    for (const span of spans) {
      if (span.start > cursor) html += this.escapeHtml(text.slice(cursor, span.start))
      html += this.renderSuggestionSpan(span.suggestion)
      cursor = span.end
    }
    if (cursor < text.length) html += this.escapeHtml(text.slice(cursor))
    return html
  }

  private renderSuggestionSpan(suggestion: QaSuggestion): string {
    if (suggestion.status === "accepted") {
      return `<span class="chapter-review__qa-suggestion chapter-review__qa-suggestion--accepted">${this.escapeHtml(suggestion.suggested_revision)}</span>`
    }

    const focusedClass = this.qaFocusedId === suggestion.id ? " chapter-review__qa-suggestion--focused" : ""
    const newColorClass = suggestion.source === "editor"
      ? "chapter-review__qa-suggestion-new--editor"
      : "chapter-review__qa-suggestion-new--factcheck"

    return (
      `<span class="chapter-review__qa-suggestion${focusedClass}" data-suggestion-id="${suggestion.id}">` +
      `<span class="chapter-review__qa-suggestion-old">${this.escapeHtml(suggestion.quote)}</span> ` +
      `<span class="chapter-review__qa-suggestion-new ${newColorClass}">${this.escapeHtml(suggestion.suggested_revision)}</span>` +
      `</span>`
    )
  }

  private escapeHtml(text: string): string {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
