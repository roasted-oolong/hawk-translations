import { Controller } from "@hotwired/stimulus"

interface SearchResult {
  embeddable_type: string
  embeddable_id: number
  novel_id: number
  score: number
  record: Record<string, unknown>
}

const CATEGORY_META: Record<string, { label: string; bg: string; fg: string }> = {
  BibleCharacter:      { label: "Character",      bg: "#EFF6FF", fg: "#1d4ed8" },
  BibleLocation:       { label: "Location",        bg: "#ECFDF5", fg: "#065f46" },
  BibleTerminology:    { label: "Terminology",     bg: "#F5F3FF", fg: "#5b21b6" },
  BibleCulturalPhrase: { label: "Cultural Phrase", bg: "#FFF7ED", fg: "#9a3412" },
  BibleStoryEntry:     { label: "Story Entry",     bg: "#F0FDF4", fg: "#166534" },
}

const TYPE_PATHS: Record<string, string> = {
  BibleCharacter:      "bible_characters",
  BibleLocation:       "bible_locations",
  BibleTerminology:    "bible_terminologies",
  BibleCulturalPhrase: "bible_cultural_phrases",
  BibleStoryEntry:     "bible_story_entries",
}

interface EditFieldConfig {
  label:        string
  field:        string
  type:         "text" | "textarea"
  // Shown as input placeholder text — only consumed by the create dialog's
  // extraFields rendering today (editFormHTML doesn't need it, since those
  // inputs already carry real values), but it lives on the shared
  // EDIT_FIELDS source so it can't drift from the field list itself.
  placeholder?: string
}

const EDIT_FIELDS: Record<string, EditFieldConfig[]> = {
  BibleCharacter: [
    { label: "Name",        field: "name",        type: "text"     },
    { label: "Korean Name", field: "korean_name", type: "text"     },
    { label: "Role",        field: "role",        type: "text",     placeholder: "e.g. Protagonist, Antagonist, Supporting" },
    { label: "Aliases",     field: "aliases",     type: "text",     placeholder: "Other names or titles this character goes by" },
    { label: "Notes",       field: "notes",       type: "textarea", placeholder: "Honorifics, naming conventions, what to avoid…" },
  ],
  BibleLocation: [
    { label: "Name",         field: "name",         type: "text"     },
    { label: "Korean Name",  field: "korean_name",  type: "text"     },
    { label: "Significance", field: "significance", type: "textarea", placeholder: "Physical description and story significance…" },
    { label: "Notes",        field: "notes",        type: "textarea", placeholder: "Preferred rendering, alternatives to avoid…" },
  ],
  BibleTerminology: [
    { label: "Term",        field: "term",        type: "text"     },
    { label: "Korean Term", field: "korean_term", type: "text"     },
    { label: "Definition",  field: "definition",  type: "textarea", placeholder: "What this term means and how it works in the story…" },
    { label: "Usage Notes", field: "usage_notes", type: "textarea", placeholder: "Do not translate as… / Retain as… / Capitalisation rules…" },
    { label: "Notes",       field: "notes",       type: "textarea", placeholder: "Any other context worth flagging" },
  ],
  BibleCulturalPhrase: [
    { label: "Phrase",                  field: "phrase",                  type: "text"     },
    { label: "Korean Phrase",           field: "korean_phrase",           type: "text"     },
    { label: "Established Translation", field: "established_translation", type: "text",     placeholder: "e.g. eating elevation for a week" },
    { label: "Intended Meaning",        field: "intended_meaning",        type: "textarea", placeholder: "Literal meaning and intended nuance…" },
    { label: "Notes",                   field: "notes",                   type: "textarea", placeholder: "When it's used, author's preferred rendering, recurrence…" },
  ],
  BibleStoryEntry: [
    { label: "Title",    field: "title",    type: "text"     },
    { label: "Category", field: "category", type: "text",     placeholder: "e.g. Timeline, Continuity, World rule" },
    { label: "Content",  field: "content",  type: "textarea", placeholder: "Story note, timeline entry, continuity flag…" },
    { label: "Notes",    field: "notes",    type: "textarea", placeholder: "Why this matters, what to watch for, confidence level…" },
  ],
}

interface CreateTypeConfig {
  modelType:          string
  label:              string
  path:               string
  param:              string
  englishField:       string
  englishLabel:       string
  englishPlaceholder: string
  koreanField:        string | null
  koreanLabel:        string | null
  koreanPlaceholder:  string | null
  // The rest of EDIT_FIELDS[modelType], beyond english/korean — shown in
  // the quick-create form so it can prefill from Pipeline::BibleEntrySuggestion,
  // not just the two fields it used to have. Derived below, not hand-listed,
  // so the create and edit forms can never drift out of sync on field sets.
  extraFields:        EditFieldConfig[]
}

const CREATE_TYPE_SOURCE: Array<Omit<CreateTypeConfig, "extraFields">> = [
  { modelType: "BibleCharacter",      label: "Character",       path: "bible_characters",       param: "bible_character",       englishField: "name",   englishLabel: "English Name", englishPlaceholder: "e.g. Ryu Seongjun",                koreanField: "korean_name",   koreanLabel: "Korean Name",   koreanPlaceholder: "e.g. 류성준"    },
  { modelType: "BibleLocation",       label: "Location",        path: "bible_locations",        param: "bible_location",        englishField: "name",   englishLabel: "English Name", englishPlaceholder: "e.g. Crimson Peak",                koreanField: "korean_name",   koreanLabel: "Korean Name",   koreanPlaceholder: "e.g. 붉은 봉우리" },
  { modelType: "BibleTerminology",    label: "Terminology",     path: "bible_terminologies",    param: "bible_terminology",     englishField: "term",   englishLabel: "Term",         englishPlaceholder: "e.g. Phoenix Flame",               koreanField: "korean_term",   koreanLabel: "Korean Term",   koreanPlaceholder: "e.g. 봉황의 불꽃" },
  { modelType: "BibleCulturalPhrase", label: "Cultural Phrase", path: "bible_cultural_phrases", param: "bible_cultural_phrase", englishField: "phrase", englishLabel: "Phrase",       englishPlaceholder: "e.g. eating elevation for a week", koreanField: "korean_phrase", koreanLabel: "Korean Phrase", koreanPlaceholder: "e.g. 고도를 씹다" },
  { modelType: "BibleStoryEntry",     label: "Story Entry",     path: "bible_story_entries",    param: "bible_story_entry",     englishField: "title",  englishLabel: "Title",        englishPlaceholder: "Short descriptive title",          koreanField: null,            koreanLabel: null,            koreanPlaceholder: null              },
]

const CREATE_TYPE_CONFIG: CreateTypeConfig[] = CREATE_TYPE_SOURCE.map(source => ({
  ...source,
  extraFields: (EDIT_FIELDS[source.modelType] ?? [])
    .filter(f => f.field !== source.englishField && f.field !== source.koreanField),
}))

const TYPE_PARAMS: Record<string, string> = {
  BibleCharacter:      "bible_character",
  BibleLocation:       "bible_location",
  BibleTerminology:    "bible_terminology",
  BibleCulturalPhrase: "bible_cultural_phrase",
  BibleStoryEntry:     "bible_story_entry",
}

function esc(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function displayName(type: string, r: Record<string, unknown>): string {
  switch (type) {
    case "BibleCharacter":      return String(r["name"]   ?? "")
    case "BibleLocation":       return String(r["name"]   ?? "")
    case "BibleTerminology":    return String(r["term"]   ?? "")
    case "BibleCulturalPhrase": return String(r["phrase"] ?? "")
    case "BibleStoryEntry":     return String(r["title"]  ?? "")
    default:                    return ""
  }
}

function koreanName(type: string, r: Record<string, unknown>): string {
  switch (type) {
    case "BibleCharacter":      return String(r["korean_name"]   ?? "")
    case "BibleLocation":       return String(r["korean_name"]   ?? "")
    case "BibleTerminology":    return String(r["korean_term"]   ?? "")
    case "BibleCulturalPhrase": return String(r["korean_phrase"] ?? "")
    default:                    return ""
  }
}

function snippet(type: string, r: Record<string, unknown>): string {
  let text = ""
  switch (type) {
    case "BibleCharacter":      text = String(r["role"]             ?? r["notes"]               ?? ""); break
    case "BibleLocation":       text = String(r["description"]      ?? r["notes"]               ?? ""); break
    case "BibleTerminology":    text = String(r["definition"]       ?? r["notes"]               ?? ""); break
    case "BibleCulturalPhrase": text = String(r["intended_meaning"] ?? r["literal_translation"] ?? r["notes"] ?? ""); break
    case "BibleStoryEntry":     text = String(r["content"]          ?? r["notes"]               ?? ""); break
  }
  return text.length > 90 ? text.slice(0, 90).trimEnd() + "…" : text
}

function detailFields(type: string, r: Record<string, unknown>): Array<{ label: string; value: string }> {
  const f = (label: string, v: unknown) => ({ label, value: String(v ?? "").trim() })
  const rows = (() => {
    switch (type) {
      case "BibleCharacter":
        return [ f("Role", r["role"]), f("Aliases", r["aliases"]), f("Significance", r["significance"]), f("Notes", r["notes"]) ]
      case "BibleLocation":
        return [ f("Type", r["location_type"]), f("Description", r["description"]), f("Significance", r["significance"]), f("Notes", r["notes"]) ]
      case "BibleTerminology":
        return [ f("Definition", r["definition"]), f("Usage Notes", r["usage_notes"]), f("Notes", r["notes"]) ]
      case "BibleCulturalPhrase":
        return [ f("Meaning", r["intended_meaning"]), f("Literal", r["literal_translation"]), f("Translation", r["established_translation"]), f("Notes", r["notes"]) ]
      case "BibleStoryEntry":
        return [ f("Category", r["category"]), f("Content", r["content"]), f("Notes", r["notes"]) ]
      default:
        return []
    }
  })()
  return rows.filter(x => x.value)
}

export default class BibleLookupController extends Controller<HTMLElement> {
  static values = {
    searchUrl: String,
    novelId:   String,
  }

  declare searchUrlValue: string
  declare novelIdValue:   string

  private popover:          HTMLDivElement | null = null
  private anchorRect:       DOMRect | null = null
  private currentQuery:     string = ""
  private currentContext:   string = ""
  private currentChapterId: string | null = null
  private currentResults:   SearchResult[] = []
  private suggestionAbort:  AbortController | null = null

  // The "New Bible Entry" dialog — a native <dialog> layered above the
  // anchored popover. The popover stays mounted (just hidden) while it's
  // open, so Cancel/Escape/backdrop-click returns to the same search
  // results instead of losing them; only a successful create tears both
  // down together.
  private createDialog:    HTMLDialogElement    | null = null
  private createConfig:    CreateTypeConfig     | null = null
  private createSucceeded: boolean = false

  private taKeydown       = (e: KeyboardEvent) => this.handleTabOnTextarea(e)
  private editableKeydown = (e: KeyboardEvent) => this.handleTabOnEditable(e)
  private docEsc    = (e: KeyboardEvent) => { if (this.createDialog) return; if (e.key === "Escape") { e.preventDefault(); this.closePopover() } }
  private docClick  = (e: MouseEvent)    => { if (this.createDialog) return; if (this.popover && !this.popover.contains(e.target as Node)) this.closePopover() }

  connect() {
    this.element.querySelectorAll<HTMLTextAreaElement>("textarea").forEach(ta => {
      ta.addEventListener("keydown", this.taKeydown)
    })
    // contenteditable regions (e.g. chapter_review's QA tracked-changes pane)
    // don't have a <textarea> to hang the plain listener above off of — same
    // Tab-to-look-up behavior, wired separately since the two need different
    // selection APIs (see handleTabOnEditable).
    this.element.querySelectorAll<HTMLElement>('[contenteditable="true"]').forEach(el => {
      el.addEventListener("keydown", this.editableKeydown)
    })
  }

  disconnect() {
    this.element.querySelectorAll<HTMLTextAreaElement>("textarea").forEach(ta => {
      ta.removeEventListener("keydown", this.taKeydown)
    })
    this.element.querySelectorAll<HTMLElement>('[contenteditable="true"]').forEach(el => {
      el.removeEventListener("keydown", this.editableKeydown)
    })
    this.createDialog?.remove()
    this.createDialog = null
    this.closePopover()
  }

  // ── TAB intercept ──────────────────────────────────────────────────────────

  private handleTabOnTextarea(event: KeyboardEvent) {
    if (event.key !== "Tab") return
    const ta = event.target as HTMLTextAreaElement
    const { selectionStart, selectionEnd } = ta
    if (selectionStart === selectionEnd) return

    event.preventDefault()
    const query = ta.value.slice(selectionStart, selectionEnd).trim()
    if (query.length < 2) return

    this.currentQuery     = query
    this.currentContext   = this.surroundingContext(ta.value, selectionStart!, selectionEnd!)
    this.currentChapterId = this.resolveChapterId(ta)
    this.anchorRect       = this.selectionRect(ta, selectionStart!)
    this.openLoading()
    this.fetchResults(query)
  }

  // Mirrors handleTabOnTextarea above for contenteditable regions. A plain
  // <textarea> exposes selectionStart/selectionEnd; a contenteditable div has
  // no equivalent — the Selection API (and a Range's own, already-viewport-
  // relative getBoundingClientRect()) stands in for both the textarea's
  // slice-by-offset query text and its mirror-div selectionRect() hack below.
  private handleTabOnEditable(event: KeyboardEvent) {
    if (event.key !== "Tab") return
    const selection = window.getSelection()
    if (!selection || selection.isCollapsed) return

    event.preventDefault()
    const query = selection.toString().trim()
    if (query.length < 2) return

    const range = selection.getRangeAt(0)

    this.currentQuery     = query
    this.currentContext   = this.surroundingContextForRange(range, query)
    this.currentChapterId = this.resolveChapterId(event.target as HTMLElement)
    this.anchorRect       = range.getBoundingClientRect()
    this.openLoading()
    this.fetchResults(query)
  }

  // Walks up from wherever the selection was made to the nearest
  // data-chapter-id — chapter_review stamps this on each per-chapter pane
  // (it's a multi-chapter slideshow); the single-chapter editor
  // (chapters#show) stamps it once on its root. Returns null off any page
  // that hasn't wired this in, which just means suggestions are skipped —
  // the rest of the quick-create form still works exactly as before.
  private resolveChapterId(origin: HTMLElement): string | null {
    return origin.closest<HTMLElement>("[data-chapter-id]")?.dataset.chapterId ?? null
  }

  // ~200 chars either side of the selection — enough for
  // Pipeline::BibleEntrySuggestion to disambiguate which occurrence/sense
  // was selected, not meant to be a precise sentence/paragraph boundary.
  private surroundingContext(fullText: string, start: number, end: number): string {
    const CONTEXT_CHARS = 200
    return fullText.slice(Math.max(0, start - CONTEXT_CHARS), Math.min(fullText.length, end + CONTEXT_CHARS))
  }

  // contenteditable has no flat string + offsets to slice the way a
  // <textarea> does — best-effort substitute: the text of the block
  // element containing the selection, falling back to the selection
  // itself if that can't be found.
  private surroundingContextForRange(range: Range, fallback: string): string {
    const container = range.commonAncestorContainer
    const el = container.nodeType === Node.ELEMENT_NODE ? (container as Element) : container.parentElement
    return el?.closest<HTMLElement>("p, div, li, td")?.textContent?.trim() || fallback
  }

  // ── Popover lifecycle ──────────────────────────────────────────────────────

  private openLoading() {
    this.closePopover()

    const pop = document.createElement("div")
    pop.className = "bible-lookup"
    pop.setAttribute("role", "dialog")
    pop.setAttribute("aria-label", "Bible lookup")
    pop.innerHTML = this.headerHTML() + `<div class="bible-lookup__body">${this.loadingHTML()}</div>`
    document.body.appendChild(pop)
    this.popover = pop

    pop.querySelector<HTMLButtonElement>(".bible-lookup__close")
      ?.addEventListener("click", () => this.closePopover())

    document.addEventListener("keydown", this.docEsc)
    document.addEventListener("mousedown", this.docClick)

    this.reposition()
  }

  private closePopover() {
    this.popover?.remove()
    this.popover = null
    this.suggestionAbort?.abort()
    this.suggestionAbort = null
    document.removeEventListener("keydown", this.docEsc)
    document.removeEventListener("mousedown", this.docClick)
  }

  private reposition() {
    const pop  = this.popover
    const rect = this.anchorRect
    if (!pop || !rect) return

    const margin = 8
    const popW   = pop.offsetWidth  || 320
    const popH   = pop.offsetHeight || 160

    const useAbove = rect.top > window.innerHeight / 2 && rect.top >= popH + margin
    const rawTop   = useAbove ? rect.top - popH - margin : rect.bottom + margin
    const top      = Math.max(margin, Math.min(rawTop, window.innerHeight - popH - margin))
    const left     = Math.max(margin, Math.min(rect.left, window.innerWidth - popW - margin))

    pop.style.top  = `${top}px`
    pop.style.left = `${left}px`
    pop.dataset.placement = useAbove ? "above" : "below"
  }

  // Measures the viewport Y of the selection start using a mirror div.
  // Needed because auto-sizing textareas expand to full chapter height,
  // making getBoundingClientRect().bottom useless for positioning.
  private selectionRect(ta: HTMLTextAreaElement, selectionStart: number): DOMRect {
    const taRect = ta.getBoundingClientRect()
    const cs     = window.getComputedStyle(ta)

    const mirror = document.createElement("div")
    mirror.style.cssText = [
      "position:absolute", "visibility:hidden", "pointer-events:none",
      "top:0", "left:-9999px",
      `width:${ta.clientWidth}px`,
      `font-family:${cs.fontFamily}`,
      `font-size:${cs.fontSize}`,
      `font-weight:${cs.fontWeight}`,
      `line-height:${cs.lineHeight}`,
      `padding:${cs.paddingTop} ${cs.paddingRight} ${cs.paddingBottom} ${cs.paddingLeft}`,
      "white-space:pre-wrap",
      "overflow-wrap:break-word",
      "box-sizing:border-box",
    ].join(";")

    mirror.textContent = ta.value.slice(0, selectionStart)
    const caret = document.createElement("span")
    caret.textContent = "​"
    mirror.appendChild(caret)
    document.body.appendChild(mirror)
    const caretOffsetY = caret.offsetTop
    document.body.removeChild(mirror)

    const lineH = parseFloat(cs.lineHeight) || 24
    const top   = taRect.top + caretOffsetY
    return new DOMRect(taRect.left, top, taRect.width, lineH)
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  private async fetchResults(query: string) {
    let results: SearchResult[] = []
    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      url.searchParams.set("limit", "5")
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (res.ok) results = (await res.json()).results ?? []
    } catch (err) {
      console.error("[BibleLookup] fetch error:", err)
    }

    this.currentResults = results
    this.renderResults(results)
  }

  private renderResults(results: SearchResult[]) {
    if (!this.popover) return
    const body = this.popover.querySelector<HTMLElement>(".bible-lookup__body")
    if (!body) return

    body.innerHTML = results.length > 0 ? this.resultsHTML(results) : this.emptyHTML()

    body.querySelectorAll<HTMLButtonElement>("[data-result-idx]").forEach(btn => {
      btn.addEventListener("click", () => {
        const idx = parseInt(btn.dataset.resultIdx ?? "0", 10)
        if (results[idx]) this.showDetail(results[idx])
      })
    })

    body.querySelectorAll<HTMLButtonElement>("[data-create-type]").forEach(btn => {
      btn.addEventListener("click", () => {
        const config = CREATE_TYPE_CONFIG.find(c => c.path === btn.dataset.createType)
        if (config) this.openCreateDialog(config)
      })
    })

    this.reposition()
  }

  // ── HTML builders ──────────────────────────────────────────────────────────

  private headerHTML(): string {
    const q = this.currentQuery.length > 28 ? this.currentQuery.slice(0, 28) + "…" : this.currentQuery
    return `
      <div class="bible-lookup__header">
        <div class="bible-lookup__header-left">
          <svg class="bible-lookup__book-icon" xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>
          </svg>
          <span class="bible-lookup__query">${esc(q)}</span>
        </div>
        <button class="bible-lookup__close" aria-label="Close lookup" type="button">
          <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>`
  }

  private loadingHTML(): string {
    return `
      <div class="bible-lookup__loading">
        <span class="bible-lookup__spinner" aria-hidden="true"></span>
        <span>Looking up…</span>
      </div>`
  }

  private resultsHTML(results: SearchResult[]): string {
    const count = results.length
    const cards = results.map((r, idx) => {
      const meta = CATEGORY_META[r.embeddable_type] ?? { label: r.embeddable_type, bg: "#F1F5F9", fg: "#475569" }
      const name = displayName(r.embeddable_type, r.record)
      const ko   = koreanName(r.embeddable_type, r.record)
      const snip = snippet(r.embeddable_type, r.record)
      return `
        <div class="bible-lookup__card">
          <div class="bible-lookup__card-top">
            <div class="bible-lookup__card-left">
              <span class="bible-lookup__badge" style="background:${esc(meta.bg)};color:${esc(meta.fg)}">${esc(meta.label)}</span>
              <span class="bible-lookup__card-name">${esc(name)}</span>
            </div>
            ${ko ? `<span class="bible-lookup__card-korean" lang="ko">${esc(ko)}</span>` : ""}
          </div>
          ${snip ? `<p class="bible-lookup__card-snippet">${esc(snip)}</p>` : ""}
          <button class="bible-lookup__view-btn" data-result-idx="${idx}" type="button">
            View entry
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6"/></svg>
          </button>
        </div>`
    }).join("")
    return `
      <div class="bible-lookup__results-bar">
        <span class="bible-lookup__results-count">${count} ${count === 1 ? "match" : "matches"}</span>
      </div>
      <div class="bible-lookup__results">${cards}</div>`
  }

  private emptyHTML(): string {
    const q    = this.currentQuery.length > 22 ? this.currentQuery.slice(0, 22) + "…" : this.currentQuery
    const btns = CREATE_TYPE_CONFIG.map(t =>
      `<button class="bible-lookup__create-btn" data-create-type="${esc(t.path)}" type="button">${esc(t.label)}</button>`
    ).join("")
    return `
      <div class="bible-lookup__empty">
        <p class="bible-lookup__empty-msg">No entry found for <strong>"${esc(q)}"</strong></p>
        <p class="bible-lookup__create-label">Create as</p>
        <div class="bible-lookup__create-btns">${btns}</div>
      </div>`
  }

  // ── "New Bible Entry" dialog ────────────────────────────────────────────────
  //
  // A native <dialog>, opened over the anchored popover rather than swapping
  // its body — see hawk-translations-ui-prototype's bible-lookup-popover.tsx
  // CreateEntryModal, the reference for this shell/pill/footer convention
  // (DECISIONS.md 2026-08-08 bible-lookup-modal entry). Production keeps its
  // real per-type field sets rather than that prototype's generic 4-field
  // shape, and keeps English (not Korean) as the required, prefilled field —
  // it's what's actually selected in this app's English-first workflow.

  private openCreateDialog(config: CreateTypeConfig) {
    this.createConfig    = config
    this.createSucceeded = false
    this.popover?.classList.add("bible-lookup--hidden")

    const dialog = document.createElement("dialog")
    dialog.className = "bible-lookup-create-dialog"
    dialog.setAttribute("aria-label", "New Bible Entry")
    dialog.innerHTML = this.createDialogHTML(config)
    document.body.appendChild(dialog)
    this.createDialog = dialog

    dialog.addEventListener("click", (e) => { if (e.target === dialog) dialog.close() })
    dialog.addEventListener("close", () => this.teardownCreateDialog())
    dialog.querySelector<HTMLButtonElement>(".bible-lookup-create-dialog__close")
      ?.addEventListener("click", () => dialog.close())
    dialog.querySelector<HTMLButtonElement>(".bible-lookup-create-dialog__cancel")
      ?.addEventListener("click", () => dialog.close())
    dialog.querySelector<HTMLFormElement>(".bible-lookup-create-dialog__form")
      ?.addEventListener("submit", (e) => { e.preventDefault(); this.submitCreateForm(dialog) })
    this.wirePillButtons(dialog)
    this.wireRequiredField(dialog, config)

    dialog.showModal()
    dialog.querySelector<HTMLInputElement>(".bible-lookup-create-dialog__input")?.focus()
    this.fetchSuggestion(dialog)
  }

  // Fired on every dialog close, however it happened (X, Cancel, backdrop
  // click, Escape, or — after a successful create — the timed close in
  // showCreateSuccess). createSucceeded tells the two apart: a real create
  // tears the anchored popover down with it; anything else just un-hides it
  // so the user lands back on the same search results.
  private teardownCreateDialog() {
    this.suggestionAbort?.abort()
    this.suggestionAbort = null
    this.createDialog?.remove()
    this.createDialog = null
    this.createConfig = null

    if (this.createSucceeded) {
      this.closePopover()
    } else {
      this.popover?.classList.remove("bible-lookup--hidden")
      this.reposition()
    }
  }

  private createDialogHTML(config: CreateTypeConfig): string {
    const meta = CATEGORY_META[config.modelType] ?? { label: config.label, bg: "#F1F5F9", fg: "#475569" }
    return `
      <div class="bible-lookup-create-dialog__panel">
        <form class="bible-lookup-create-dialog__form">
          <div class="bible-lookup-create-dialog__header">
            <h2 class="bible-lookup-create-dialog__title">
              New Bible Entry
              <span class="bible-lookup__badge bible-lookup-create-dialog__badge" style="background:${esc(meta.bg)};color:${esc(meta.fg)}">${esc(meta.label)}</span>
            </h2>
            <button class="bible-lookup-create-dialog__close" type="button" aria-label="Close">
              <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
            </button>
          </div>
          <div class="bible-lookup-create-dialog__pills">${this.createPillsHTML(config)}</div>
          <div class="bible-lookup-create-dialog__divider"></div>
          <div class="bible-lookup-create-dialog__body">${this.createDialogFieldsHTML(config)}</div>
          <div class="bible-lookup-create-dialog__actions">
            <button class="btn btn--ghost btn--sm bible-lookup-create-dialog__cancel" type="button">Cancel</button>
            <button class="btn btn--primary btn--sm bible-lookup-create-dialog__submit" type="submit">Save to Bible</button>
          </div>
        </form>
      </div>`
  }

  private createPillsHTML(active: CreateTypeConfig): string {
    return CREATE_TYPE_CONFIG.map(t => `
      <button class="bible-lookup-create-dialog__pill${t.path === active.path ? " bible-lookup-create-dialog__pill--active" : ""}" data-pill-type="${esc(t.path)}" type="button">${esc(t.label)}</button>
    `).join("")
  }

  private createDialogFieldsHTML(config: CreateTypeConfig): string {
    const koreanRow = config.koreanField ? `
      <div class="bible-lookup-create-dialog__field">
        <label class="bible-lookup-create-dialog__label">${esc(config.koreanLabel!)}</label>
        <input class="bible-lookup-create-dialog__input bible-lookup-create-dialog__input--korean" data-field="${esc(config.koreanField)}" type="text" autocomplete="off" lang="ko" placeholder="${esc(config.koreanPlaceholder ?? "")}">
      </div>
      <p class="bible-lookup-create-dialog__suggesting" data-qc-suggesting hidden>
        <span class="bible-lookup__spinner" aria-hidden="true"></span>
        Suggesting from the chapter's Korean source…
      </p>` : ""

    const extraRows = config.extraFields.map(f => {
      const placeholder = esc(f.placeholder ?? "")
      const input = f.type === "textarea"
        ? `<textarea class="bible-lookup-create-dialog__input" data-field="${esc(f.field)}" rows="2" placeholder="${placeholder}"></textarea>`
        : `<input class="bible-lookup-create-dialog__input" data-field="${esc(f.field)}" type="text" autocomplete="off" placeholder="${placeholder}">`
      return `
        <div class="bible-lookup-create-dialog__field">
          <label class="bible-lookup-create-dialog__label">${esc(f.label)}</label>
          ${input}
        </div>`
    }).join("")

    return `
      <div class="bible-lookup-create-dialog__field">
        <label class="bible-lookup-create-dialog__label">
          ${esc(config.englishLabel)}
          <span class="bible-lookup-create-dialog__required">*</span>
        </label>
        <input class="bible-lookup-create-dialog__input" data-field="${esc(config.englishField)}" type="text" value="${esc(this.currentQuery)}" autocomplete="off" placeholder="${esc(config.englishPlaceholder)}">
      </div>
      ${koreanRow}
      ${extraRows}`
  }

  private wirePillButtons(dialog: HTMLDialogElement) {
    dialog.querySelectorAll<HTMLButtonElement>("[data-pill-type]").forEach(btn => {
      btn.addEventListener("click", () => {
        const next = CREATE_TYPE_CONFIG.find(c => c.path === btn.dataset.pillType)
        if (next && next.path !== this.createConfig?.path) this.switchCreateType(next)
      })
    })
  }

  // Only the identifier text (English, prefilled from the selection) carries
  // over across a type switch — the extra fields (role, notes, etc.) don't
  // map from one type's shape to another, so they reset.
  private switchCreateType(next: CreateTypeConfig) {
    const dialog = this.createDialog
    const prev   = this.createConfig
    if (!dialog || !prev) return

    const englishValue = dialog.querySelector<HTMLInputElement>(`[data-field="${prev.englishField}"]`)?.value.trim() || this.currentQuery
    this.createConfig = next

    const meta  = CATEGORY_META[next.modelType] ?? { label: next.label, bg: "#F1F5F9", fg: "#475569" }
    const badge = dialog.querySelector<HTMLElement>(".bible-lookup-create-dialog__badge")
    if (badge) {
      badge.textContent      = meta.label
      badge.style.background = meta.bg
      badge.style.color      = meta.fg
    }

    const pillsEl = dialog.querySelector<HTMLElement>(".bible-lookup-create-dialog__pills")
    if (pillsEl) {
      pillsEl.innerHTML = this.createPillsHTML(next)
      this.wirePillButtons(dialog)
    }

    const bodyEl = dialog.querySelector<HTMLElement>(".bible-lookup-create-dialog__body")
    if (bodyEl) bodyEl.innerHTML = this.createDialogFieldsHTML(next)

    const englishInput = dialog.querySelector<HTMLInputElement>(`[data-field="${next.englishField}"]`)
    if (englishInput) englishInput.value = englishValue

    this.wireRequiredField(dialog, next)
    this.fetchSuggestion(dialog)
  }

  // Save is disabled until the required (English) field has something in
  // it — mirrors the prototype's disabled-until-filled Save button.
  private wireRequiredField(dialog: HTMLDialogElement, config: CreateTypeConfig) {
    const input  = dialog.querySelector<HTMLInputElement>(`[data-field="${config.englishField}"]`)
    const submit = dialog.querySelector<HTMLButtonElement>(".bible-lookup-create-dialog__submit")
    const sync = () => { if (submit) submit.disabled = !input?.value.trim() }
    input?.addEventListener("input", sync)
    sync()
  }

  // Fires the moment the create dialog opens (and again on every type
  // switch), in parallel with the user being able to type/submit right
  // away — this is best-effort enrichment, never a gate on creating the
  // entry. Aborts any suggestion still in flight first, so a late response
  // can never land fields in the wrong (or since-switched-away-from) type.
  private fetchSuggestion(dialog: HTMLDialogElement) {
    this.suggestionAbort?.abort()
    this.suggestionAbort = null
    const config = this.createConfig
    if (!config || !config.koreanField || !this.currentChapterId) return

    const suggestingEl = dialog.querySelector<HTMLElement>("[data-qc-suggesting]")
    if (suggestingEl) suggestingEl.hidden = false

    const abort = new AbortController()
    this.suggestionAbort = abort
    const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""

    fetch(`/novels/${this.novelIdValue}/bible_entry_suggestion`, {
      method:  "POST",
      headers: { "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded", "X-CSRF-Token": csrfToken },
      body: new URLSearchParams({
        type:       config.param,
        english:    this.currentQuery,
        context:    this.currentContext,
        chapter_id: this.currentChapterId,
      }),
      signal: abort.signal,
    })
      .then(res => res.ok ? res.json() : { fields: {} })
      .then(data => {
        if (suggestingEl) suggestingEl.hidden = true
        const fields = (data?.fields ?? {}) as Record<string, string>
        Object.entries(fields).forEach(([field, value]) => {
          const el = dialog.querySelector<HTMLInputElement | HTMLTextAreaElement>(`[data-field="${field}"]`)
          // The user's own typing always wins over a late-arriving suggestion.
          if (el && el.value.trim() === "") el.value = value
        })
      })
      .catch(() => {
        // Aborted (dialog closed/type switched) or a network error —
        // either way the form just stays exactly as it was before this
        // feature existed, not an error surfaced to the user.
        if (suggestingEl) suggestingEl.hidden = true
      })
  }

  private async submitCreateForm(dialog: HTMLDialogElement) {
    const config = this.createConfig
    if (!config) return

    const submitBtn = dialog.querySelector<HTMLButtonElement>(".bible-lookup-create-dialog__submit")
    if (submitBtn) { submitBtn.disabled = true; submitBtn.textContent = "Creating…" }

    const formData = new FormData()
    formData.set(
      `${config.param}[${config.englishField}]`,
      dialog.querySelector<HTMLInputElement>(`[data-field="${config.englishField}"]`)?.value.trim() ?? ""
    )

    const restFields = [ config.koreanField, ...config.extraFields.map(f => f.field) ]
      .filter((field): field is string => !!field)
    restFields.forEach(field => {
      const el  = dialog.querySelector<HTMLInputElement | HTMLTextAreaElement>(`[data-field="${field}"]`)
      const val = el?.value.trim()
      if (val) formData.set(`${config.param}[${field}]`, val)
    })

    if (this.currentChapterId) formData.set("chapter_id", this.currentChapterId)

    const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""

    try {
      const res  = await fetch(`/novels/${this.novelIdValue}/${config.path}`, {
        method:  "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken },
        body:    formData,
      })
      const data = await res.json()

      if (res.ok) {
        this.showCreateSuccess(dialog, data.display_name as string, data.edit_url as string)
      } else {
        const msg = (data.errors as string[] | undefined)?.join(", ") ?? "Couldn't create entry."
        let errEl = dialog.querySelector<HTMLParagraphElement>(".bible-lookup-create-dialog__error")
        if (!errEl) {
          errEl = document.createElement("p")
          errEl.className = "bible-lookup-create-dialog__error"
          dialog.querySelector(".bible-lookup-create-dialog__actions")?.before(errEl)
        }
        errEl.textContent = msg
        if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = "Save to Bible" }
      }
    } catch {
      if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = "Save to Bible" }
    }
  }

  // ── Inline entry detail ────────────────────────────────────────────────────

  private showDetail(result: SearchResult) {
    const body = this.popover?.querySelector<HTMLElement>(".bible-lookup__body")
    if (!body) return

    body.innerHTML = this.detailHTML(result)

    body.querySelector<HTMLButtonElement>(".bible-lookup__detail-back")
      ?.addEventListener("click", () => this.renderResults(this.currentResults))

    body.querySelector<HTMLButtonElement>(".bible-lookup__detail-edit")
      ?.addEventListener("click", () => this.showEditForm(result))

    this.reposition()
  }

  private detailHTML(result: SearchResult): string {
    const meta    = CATEGORY_META[result.embeddable_type] ?? { label: result.embeddable_type, bg: "#F1F5F9", fg: "#475569" }
    const name    = displayName(result.embeddable_type, result.record)
    const ko      = koreanName(result.embeddable_type, result.record)
    const fields  = detailFields(result.embeddable_type, result.record)
    const segment = TYPE_PATHS[result.embeddable_type] ?? ""
    const base    = `/novels/${result.novel_id}/${segment}/${result.embeddable_id}`
    const chapter = result.record["first_appearance_chapter"]

    const fieldRows = fields.map(({ label, value }) => {
      const display = value.length > 200 ? value.slice(0, 200).trimEnd() + "…" : value
      return `
        <div class="bible-lookup__detail-field">
          <span class="bible-lookup__detail-field-label">${esc(label)}</span>
          <span class="bible-lookup__detail-field-value">${esc(display)}</span>
        </div>`
    }).join("")

    const chevron = `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6"/></svg>`

  return `
      <div class="bible-lookup__detail">
        <div class="bible-lookup__detail-header">
          <button class="bible-lookup__detail-back" type="button">
            <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="15 18 9 12 15 6"/></svg>
            Back
          </button>
          <span class="bible-lookup__badge" style="background:${esc(meta.bg)};color:${esc(meta.fg)}">${esc(meta.label)}</span>
        </div>
        <div class="bible-lookup__detail-body">
          <div class="bible-lookup__detail-name">
            <span class="bible-lookup__detail-title">${esc(name)}</span>
            ${ko      ? `<span class="bible-lookup__detail-korean" lang="ko">${esc(ko)}</span>` : ""}
            ${chapter ? `<span class="bible-lookup__detail-chapter">Ch. ${esc(String(chapter))}</span>` : ""}
          </div>
          ${fields.length === 0
            ? `<p class="bible-lookup__detail-empty">No details filled in yet.</p>`
            : `<div class="bible-lookup__detail-fields">${fieldRows}</div>`}
        </div>
        <div class="bible-lookup__detail-links">
          <button class="bible-lookup__view-link bible-lookup__detail-edit" type="button">
            Edit ${chevron}
          </button>
          <a class="bible-lookup__view-link" href="${esc(base)}" target="_blank" rel="noopener noreferrer">
            View full entry ${chevron}
          </a>
        </div>
      </div>`
  }

  // ── Inline entry edit ─────────────────────────────────────────────────────

  private showEditForm(result: SearchResult) {
    const body = this.popover?.querySelector<HTMLElement>(".bible-lookup__body")
    if (!body) return

    body.innerHTML = this.editFormHTML(result)

    body.querySelector<HTMLButtonElement>(".bible-lookup__qc-back")
      ?.addEventListener("click", () => this.showDetail(result))

    body.querySelector<HTMLFormElement>(".bible-lookup__qc-form")
      ?.addEventListener("submit", (e) => { e.preventDefault(); this.submitEditForm(result, body) })

    body.querySelector<HTMLElement>(".bible-lookup__qc-input")?.focus()
    this.reposition()
  }

  private editFormHTML(result: SearchResult): string {
    const meta   = CATEGORY_META[result.embeddable_type] ?? { label: result.embeddable_type, bg: "#F1F5F9", fg: "#475569" }
    const fields = EDIT_FIELDS[result.embeddable_type] ?? []

    const fieldRows = fields.map(({ label, field, type }) => {
      const value = String(result.record[field] ?? "")
      const input = type === "textarea"
        ? `<textarea class="bible-lookup__qc-input" data-field="${esc(field)}" rows="2">${esc(value)}</textarea>`
        : `<input class="bible-lookup__qc-input" data-field="${esc(field)}" type="text" value="${esc(value)}" autocomplete="off">`
      return `
        <div class="bible-lookup__qc-field">
          <label class="bible-lookup__qc-label">${esc(label)}</label>
          ${input}
        </div>`
    }).join("")

    return `
      <form class="bible-lookup__qc-form">
        <div class="bible-lookup__qc-header">
          <button class="bible-lookup__qc-back" type="button">
            <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="15 18 9 12 15 6"/></svg>
            Back
          </button>
          <span class="bible-lookup__qc-type-label">Edit ${esc(meta.label)}</span>
        </div>
        <div class="bible-lookup__qc-fields bible-lookup__qc-fields--scrollable">
          ${fieldRows}
        </div>
        <div class="bible-lookup__qc-footer">
          <button class="bible-lookup__qc-submit" type="submit">Save changes</button>
        </div>
      </form>`
  }

  private async submitEditForm(result: SearchResult, body: HTMLElement) {
    const segment   = TYPE_PATHS[result.embeddable_type] ?? ""
    const param     = TYPE_PARAMS[result.embeddable_type] ?? ""
    const fields    = EDIT_FIELDS[result.embeddable_type] ?? []
    const submitBtn = body.querySelector<HTMLButtonElement>(".bible-lookup__qc-submit")

    if (submitBtn) { submitBtn.disabled = true; submitBtn.textContent = "Saving…" }

    const formData  = new FormData()
    const newValues: Record<string, string> = {}
    fields.forEach(({ field }) => {
      const el  = body.querySelector<HTMLInputElement | HTMLTextAreaElement>(`[data-field="${field}"]`)
      const val = el?.value.trim() ?? ""
      formData.set(`${param}[${field}]`, val)
      newValues[field] = val
    })

    const csrfToken = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""

    try {
      const res  = await fetch(`/novels/${result.novel_id}/${segment}/${result.embeddable_id}`, {
        method:  "PATCH",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken },
        body:    formData,
      })
      const data = await res.json()

      if (res.ok) {
        fields.forEach(({ field }) => { result.record[field] = newValues[field] })
        const idx = this.currentResults.findIndex(r =>
          r.embeddable_type === result.embeddable_type && r.embeddable_id === result.embeddable_id)
        if (idx >= 0) this.currentResults[idx] = { ...result }
        this.showDetail(result)
      } else {
        const msg = (data.errors as string[] | undefined)?.join(", ") ?? "Couldn't save changes."
        let errEl = body.querySelector<HTMLParagraphElement>(".bible-lookup__qc-error")
        if (!errEl) {
          errEl = document.createElement("p")
          errEl.className = "bible-lookup__qc-error"
          body.querySelector(".bible-lookup__qc-footer")?.prepend(errEl)
        }
        errEl.textContent = msg
        if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = "Save changes" }
      }
    } catch {
      if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = "Save changes" }
    }
  }

  // Replaces the dialog's panel content with a confirmation, then closes
  // it (and, via teardownCreateDialog's createSucceeded check, the
  // anchored popover behind it) after a short delay.
  private showCreateSuccess(dialog: HTMLDialogElement, displayName: string, editUrl: string) {
    const panel = dialog.querySelector<HTMLElement>(".bible-lookup-create-dialog__panel")
    if (!panel) return

    panel.innerHTML = `
      <div class="bible-lookup__success">
        <svg class="bible-lookup__success-icon" xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="12" cy="12" r="10"/><polyline points="9 12 11 14 15 10"/>
        </svg>
        <p class="bible-lookup__success-msg">${esc(displayName)} added to Bible</p>
        <a class="bible-lookup__success-link" href="${esc(editUrl)}">Fill in details →</a>
      </div>`

    this.createSucceeded = true
    setTimeout(() => dialog.close(), 2500)
  }
}
