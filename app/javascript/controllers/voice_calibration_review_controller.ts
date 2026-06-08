import { Controller } from "@hotwired/stimulus"

interface CalibrationCard {
  id: string
  card_type: "new_pattern" | "retirement"
  heading?: string
  passage_heading?: string
  rule?: string
  decision?: string | null
}

export default class VoiceCalibrationReviewController extends Controller<HTMLElement> {
  static values = { updateUrl: String }

  static targets = [
    "card",
    "navItem",
    "navStatus",
    "slideshowScreen",
    "summaryScreen",
    "footer",
    "prevBtn",
    "acceptBtn",
    "progressFill",
    "progressText",
    "counterText",
    "topbarTitle",
    "savedIndicator",
    "summaryDecision",
    "ruleDisplay",
    "ruleEdit",
    "editBtn",
  ]

  declare updateUrlValue: string
  declare cardTargets: HTMLElement[]
  declare navItemTargets: HTMLElement[]
  declare navStatusTargets: HTMLElement[]
  declare slideshowScreenTarget: HTMLElement
  declare summaryScreenTarget: HTMLElement
  declare footerTarget: HTMLElement
  declare prevBtnTarget: HTMLButtonElement
  declare acceptBtnTarget: HTMLButtonElement
  declare progressFillTarget: HTMLElement
  declare progressTextTarget: HTMLElement
  declare counterTextTarget: HTMLElement
  declare topbarTitleTarget: HTMLElement
  declare savedIndicatorTarget: HTMLElement
  declare summaryDecisionTargets: HTMLElement[]
  declare ruleDisplayTargets: HTMLElement[]
  declare ruleEditTargets: HTMLTextAreaElement[]
  declare editBtnTargets: HTMLButtonElement[]

  private index = 0
  private decisions = new Map<string, string>()
  private savedTimer: ReturnType<typeof setTimeout> | null = null
  private cards: CalibrationCard[] = []

  private handleKeydown = (event: KeyboardEvent) => {
    const tag = (event.target as HTMLElement).tagName
    if (tag === "TEXTAREA" || tag === "INPUT") return

    switch (event.key) {
      case "ArrowLeft":
      case "p":
      case "P":
        event.preventDefault()
        this.prev()
        break
      case "ArrowRight":
      case "a":
      case "A":
        event.preventDefault()
        this.accept()
        break
      case "s":
      case "S":
        event.preventDefault()
        this.skip()
        break
    }
  }

  connect(): void {
    const dataEl = document.getElementById("vc-cards-data")
    if (dataEl) this.cards = JSON.parse(dataEl.textContent || "[]")
    document.addEventListener("keydown", this.handleKeydown)
    this.showCard(0)
  }

  disconnect(): void {
    document.removeEventListener("keydown", this.handleKeydown)
    if (this.savedTimer) clearTimeout(this.savedTimer)
  }

  async accept(): Promise<void> {
    const card = this.cardTargets[this.index]
    if (!card) return
    const cardId  = card.dataset.cardId!
    const cardType = card.dataset.cardType!

    // Determine if rule was edited (for new_pattern cards)
    const ruleEdit    = this.ruleEditTargets[this.index]
    const ruleDisplay = this.ruleDisplayTargets[this.index]
    const isEditing   = ruleEdit && !ruleEdit.hidden
    const editedRule  = isEditing ? ruleEdit.value : ruleEdit?.value
    const originalRule = this.cards.find(c => c.id === cardId)?.rule ?? ""
    const ruleChanged = editedRule !== undefined && editedRule !== originalRule
    const decision    = (cardType === "new_pattern" && ruleChanged) ? "accepted_revised" : "accepted"

    await this.sendDecision(cardId, decision, editedRule)

    // Update rule display if it was edited
    if (ruleDisplay && editedRule !== undefined) {
      ruleDisplay.textContent = editedRule
    }
    this.cancelEdit()

    this.decisions.set(cardId, decision)
    this.updateNavStatus(this.index, decision)
    this.flashSaved()
    this.advance()
  }

  skip(): void {
    const card = this.cardTargets[this.index]
    if (!card) return
    const cardId = card.dataset.cardId!

    this.decisions.set(cardId, "skipped")
    this.updateNavStatus(this.index, "skipped")
    this.cancelEdit()
    this.advance()
  }

  prev(): void {
    if (this.index > 0) {
      this.cancelEdit()
      this.showCard(this.index - 1)
    }
  }

  jumpTo(event: Event): void {
    const btn = event.currentTarget as HTMLElement
    const i   = parseInt(btn.dataset.voiceCalibrationReviewIndexParam ?? "0", 10)
    this.cancelEdit()
    this.showCard(i)
  }

  toggleEdit(): void {
    const ruleDisplay = this.ruleDisplayTargets[this.index]
    const ruleEdit    = this.ruleEditTargets[this.index]
    const editBtn     = this.editBtnTargets[this.index]
    if (!ruleDisplay || !ruleEdit || !editBtn) return

    const isEditing = !ruleEdit.hidden
    if (isEditing) {
      ruleDisplay.hidden = false
      ruleEdit.hidden = true
      editBtn.textContent = "Edit"
    } else {
      ruleDisplay.hidden = true
      ruleEdit.hidden = false
      ruleEdit.focus()
      editBtn.textContent = "Done editing"
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  private advance(): void {
    if (this.index < this.cardTargets.length - 1) {
      this.showCard(this.index + 1)
    } else {
      this.showSummary()
    }
  }

  private showCard(i: number): void {
    this.cardTargets.forEach((card, idx) => {
      if (idx === i) card.removeAttribute("hidden")
      else card.setAttribute("hidden", "")
    })

    this.navItemTargets.forEach((btn, idx) => {
      btn.classList.toggle("vc-review__nav-item--active", idx === i)
    })

    this.index = i
    const card = this.cardTargets[i]
    const isLast = i === this.cardTargets.length - 1
    const cardType = card?.dataset.cardType ?? ""

    this.prevBtnTarget.disabled = i === 0
    this.acceptBtnTarget.textContent = isLast ? "Accept & Finish" : "Accept & Next"
    this.counterTextTarget.textContent = `Card ${i + 1} of ${this.cardTargets.length}`

    const typeLabel = cardType === "new_pattern" ? "New pattern" : "Retirement proposal"
    this.topbarTitleTarget.textContent = typeLabel

    this.updateProgress()
  }

  private showSummary(): void {
    this.slideshowScreenTarget.setAttribute("hidden", "")
    this.summaryScreenTarget.removeAttribute("hidden")
    this.footerTarget.setAttribute("hidden", "")

    this.summaryDecisionTargets.forEach(el => {
      const cardId   = el.dataset.cardId!
      const decision = this.decisions.get(cardId)
      el.textContent  = decision === "accepted" ? "Accepted" :
                        decision === "accepted_revised" ? "Accepted (revised)" :
                        decision === "skipped" ? "Skipped" : "—"
      el.className = "vc-review__summary-decision " + (
        decision?.startsWith("accepted") ? "vc-review__summary-decision--accepted" : ""
      )
    })
  }

  private updateNavStatus(i: number, decision: string): void {
    const statuses = this.navStatusTargets
    if (statuses[i]) {
      statuses[i].textContent = decision === "accepted" ? "Accepted" :
                                decision === "accepted_revised" ? "Accepted (revised)" :
                                "Skipped"
    }
  }

  private updateProgress(): void {
    const decided = this.decisions.size
    const total   = this.cardTargets.length
    this.progressTextTarget.textContent = `${decided} / ${total}`
    this.progressFillTarget.style.width = total > 0 ? `${(decided / total) * 100}%` : "0%"
  }

  private flashSaved(): void {
    this.savedIndicatorTarget.hidden = false
    if (this.savedTimer) clearTimeout(this.savedTimer)
    this.savedTimer = setTimeout(() => {
      this.savedIndicatorTarget.hidden = true
    }, 2000)
  }

  private cancelEdit(): void {
    const ruleDisplay = this.ruleDisplayTargets[this.index]
    const ruleEdit    = this.ruleEditTargets[this.index]
    const editBtn     = this.editBtnTargets[this.index]
    if (!ruleEdit) return
    ruleEdit.hidden = true
    if (ruleDisplay) ruleDisplay.hidden = false
    if (editBtn) editBtn.textContent = "Edit"
  }

  private async sendDecision(cardId: string, decision: string, rule?: string): Promise<void> {
    const url = this.updateUrlValue.replace(":card_id", encodeURIComponent(cardId))
    const body = new FormData()
    body.append("decision", decision)
    if (rule !== undefined) body.append("rule", rule)
    body.append("authenticity_token", this.csrfToken())

    try {
      await fetch(url, { method: "PATCH", body })
    } catch {
      // non-blocking — the decision is tracked client-side regardless
    }
  }

  private csrfToken(): string {
    return (document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content) ?? ""
  }
}
