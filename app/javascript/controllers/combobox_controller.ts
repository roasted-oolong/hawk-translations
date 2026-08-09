// app/javascript/controllers/combobox_controller.ts
//
// Combobox controller for bible entry search.
//
// Wires a text input to the bible search JSON endpoint, debounces input,
// renders results inline, and handles keyboard navigation.
//
// Targets:
//   input   — the <input type="text"> search field
//   results — the <ul> element that receives result <li> items
//   empty   — the "no results" message element
//
// Values:
//   url (String) — the search endpoint, e.g. /novels/1/bible/search
//
// Behaviour:
//   - Fetches when query length >= 2 characters
//   - Debounces 300ms after each keystroke
//   - Keyboard: ArrowDown/ArrowUp move through results; Enter follows the
//     focused result's link; Escape closes the results list
//   - Clicking a result navigates via its <a> href
//   - Clicking outside the component closes the results list

import { Controller } from "@hotwired/stimulus"

const CATEGORY_LABELS: Record<string, string> = {
  BibleCharacter:     "Character",
  BibleLocation:      "Location",
  BibleTerminology:   "Terminology",
  BibleCulturalPhrase: "Cultural Phrase",
  BibleStoryEntry:    "Story Entry",
}

// Derive the primary display label from a search result record.
// Each bible type uses a different column for its human-readable name.
// BibleCulturalPhrase has no English name column at all — korean_phrase is
// the whole identity (2026-08-08) — so its label is Korean, unlike every
// other type here.
function recordLabel(type: string, record: Record<string, unknown>): string {
  switch (type) {
    case "BibleCharacter":      return String(record["name"]          ?? "")
    case "BibleLocation":       return String(record["name"]          ?? "")
    case "BibleTerminology":    return String(record["term"]          ?? "")
    case "BibleCulturalPhrase": return String(record["korean_phrase"] ?? "")
    case "BibleStoryEntry":     return String(record["title"]         ?? "")
    default:                    return String(record["name"] ?? record["title"] ?? "Unknown")
  }
}

// Build the show path for a result. The controller receives the base novel
// bible search URL, e.g. /novels/42/bible/search. We derive the novel
// prefix from that and append the resource path segment.
function resourcePath(
  novelPrefix: string,
  type: string,
  id: number
): string {
  const segments: Record<string, string> = {
    BibleCharacter:      "bible_characters",
    BibleLocation:       "bible_locations",
    BibleTerminology:    "bible_terminologies",
    BibleCulturalPhrase: "bible_cultural_phrases",
    BibleStoryEntry:     "bible_story_entries",
  }
  const segment = segments[type]
  if (!segment) return "#"
  return `${novelPrefix}/${segment}/${id}`
}

export default class ComboboxController extends Controller {
  static targets = ["input", "results", "empty"]
  static values  = { url: String }

  declare readonly inputTarget:   HTMLInputElement
  declare readonly resultsTarget: HTMLElement
  declare readonly emptyTarget:   HTMLElement
  declare urlValue: string

  private debounceTimer: ReturnType<typeof setTimeout> | null = null
  private activeIndex = -1
  private resultItems: HTMLElement[] = []

  connect(): void {
    this.inputTarget.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect(): void {
    this.inputTarget.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("click", this.handleOutsideClick)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
  }

  // ---------------------------------------------------------------------------
  // Input handler — called by data-action="input->combobox#search"
  // ---------------------------------------------------------------------------
  search(): void {
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetch(), 300)
  }

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------
  private async fetch(): Promise<void> {
    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.close()
      return
    }

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)

    let data: { results?: unknown[]; error?: string }
    try {
      const response = await window.fetch(url.toString(), {
        headers: { Accept: "application/json" },
      })
      data = await response.json()
    } catch {
      this.close()
      return
    }

    this.render(data.results ?? [])
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------
  private render(results: unknown[]): void {
    this.resultsTarget.innerHTML = ""
    this.activeIndex = -1
    this.resultItems = []

    if (results.length === 0) {
      this.resultsTarget.hidden = true
      this.emptyTarget.hidden   = false
      return
    }

    this.emptyTarget.hidden   = true
    this.resultsTarget.hidden = false

    // Derive novel URL prefix from the search endpoint URL.
    // e.g. /novels/42/bible/search → /novels/42
    const novelPrefix = this.urlValue.replace(/\/bible\/search$/, "")

    results.forEach((raw) => {
      const result = raw as {
        embeddable_type: string
        embeddable_id:   number
        record:          Record<string, unknown>
      }

      const label    = recordLabel(result.embeddable_type, result.record)
      const category = CATEGORY_LABELS[result.embeddable_type] ?? result.embeddable_type
      const href     = resourcePath(novelPrefix, result.embeddable_type, result.embeddable_id)

      const li = document.createElement("li")
      li.className = "bible-search__result"
      li.setAttribute("role", "option")

      const a = document.createElement("a")
      a.href      = href
      a.className = "bible-search__result-link"

      const labelSpan = document.createElement("span")
      labelSpan.className   = "bible-search__result-label"
      labelSpan.textContent = label

      const categorySpan = document.createElement("span")
      categorySpan.className   = "bible-search__result-category"
      categorySpan.textContent = category

      a.appendChild(labelSpan)
      a.appendChild(categorySpan)
      li.appendChild(a)
      this.resultsTarget.appendChild(li)
      this.resultItems.push(li)
    })
  }

  // ---------------------------------------------------------------------------
  // Keyboard navigation
  // ---------------------------------------------------------------------------
  private handleKeydown = (event: KeyboardEvent): void => {
    if (this.resultsTarget.hidden && event.key !== "Escape") return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveActive(-1)
        break
      case "Enter":
        event.preventDefault()
        this.activateSelected()
        break
      case "Escape":
        this.close()
        break
    }
  }

  private moveActive(direction: 1 | -1): void {
    if (this.resultItems.length === 0) return

    if (this.activeIndex >= 0) {
      this.resultItems[this.activeIndex].classList.remove("bible-search__result--active")
    }

    this.activeIndex = Math.max(
      0,
      Math.min(this.activeIndex + direction, this.resultItems.length - 1)
    )

    const active = this.resultItems[this.activeIndex]
    active.classList.add("bible-search__result--active")
    active.scrollIntoView({ block: "nearest" })
  }

  private activateSelected(): void {
    if (this.activeIndex < 0) return
    const link = this.resultItems[this.activeIndex].querySelector("a")
    if (link) link.click()
  }

  // ---------------------------------------------------------------------------
  // Close
  // ---------------------------------------------------------------------------
  private close(): void {
    this.resultsTarget.hidden = true
    this.emptyTarget.hidden   = true
    this.activeIndex          = -1
    this.resultItems          = []
  }

  private handleOutsideClick = (event: MouseEvent): void => {
    if (!this.element.contains(event.target as Node)) {
      this.close()
    }
  }
}
