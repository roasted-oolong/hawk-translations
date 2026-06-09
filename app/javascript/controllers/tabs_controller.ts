// tabs_controller.ts
//
// Manages the tab strip on the novel show page.
//
// Responsibilities:
//   - Eagerly sets `src` on every panel frame during connect() so all panels
//     load immediately and are always present in the DOM (no lazy-loading per
//     click). This keeps every <turbo-frame> findable by tests and accessible
//     to assistive technology at all times.
//   - Tracks which tab is active via the `novel-tab--active` CSS class
//   - Persists the active tab key to sessionStorage, keyed per-novel, so the
//     selection survives same-session navigation away and back
//   - Ignores clicks on aria-disabled tabs entirely
//   - Reloads the review tab when chapters-table reports a higher translated
//     count than the last observed value, so the review tab updates as soon
//     as a translation job completes without requiring a page refresh.
//
// Panel visibility:
//   All panel frames have their src set eagerly in connect() so content loads
//   immediately. activateTab() toggles the HTML `hidden` attribute to show only
//   the active panel, keeping inactive frames in the DOM (preserving their
//   loaded content) while hiding them visually.
//
// HTML contract:
//   The controller mounts on the tab strip wrapper:
//     <div data-controller="tabs"
//          data-tabs-novel-id-value="<%= @novel.id %>">
//
//   Each clickable tab button:
//     <button data-action="click->tabs#select"
//             data-tabs-key-param="chapters"
//             data-testid="tab-chapters"
//             aria-controls="tab-panel-chapters">
//
//   Each Turbo Frame panel (no `hidden` attribute; src set by controller):
//     <turbo-frame id="tab-panel-chapters"
//                  data-tabs-src-value="<%= novel_chapters_path(@novel) %>"
//                  data-testid="tab-panel-chapters">
//     </turbo-frame>
//
//   chapters-table frame must contain an element with data-translated-count so
//   this controller can detect when new translations complete. Must be on an
//   inner element — Turbo only replaces inner content, not frame attributes:
//     <div data-translated-count="<%= @chapters.count(&:translated?) %>">
//
//   Disabled tabs carry aria-disabled="true" and no data-action.
//   The controller guards against them explicitly, but they should not fire
//   because no data-action is wired.
//
// sessionStorage key: `novel-tab-${novelId}`

import { Controller } from "@hotwired/stimulus"

export default class TabsController extends Controller {
  static values = {
    novelId: { type: Number, default: 0 },
  }

  declare novelIdValue: number

  private lastTranslatedCount = -1
  private boundOnFrameLoad!: (e: Event) => void

  private get storageKey(): string {
    return `novel-tab-${this.novelIdValue}`
  }

  connect(): void {
    // Eagerly wire src on every panel frame so all frames are loaded and
    // findable immediately — no deferred loading on first click.
    this.allPanelFrames().forEach(frame => {
      if (!frame.getAttribute("src")) {
        const srcValue = frame.getAttribute("data-tabs-src-value")
        if (srcValue) frame.setAttribute("src", srcValue)
      }
    })

    const saved = this.novelIdValue > 0
      ? sessionStorage.getItem(this.storageKey)
      : null

    // Default to "chapters" if nothing is stored or the stored key is unknown.
    const initialKey = saved && this.tabButtonFor(saved) ? saved : "chapters"
    this.activateTab(initialKey)

    this.boundOnFrameLoad = this.onFrameLoad.bind(this)
    document.addEventListener("turbo:frame-load", this.boundOnFrameLoad)
  }

  disconnect(): void {
    document.removeEventListener("turbo:frame-load", this.boundOnFrameLoad)
  }

  // Called via data-action="click->tabs#select" on each enabled tab.
  // The tab key is read from data-tabs-key-param on the button element itself,
  // via dataset (camelCased: tabsKeyParam). Using dataset avoids relying on
  // Stimulus's ActionEvent params type, keeping this compatible with the plain
  // Event type the rest of the codebase uses.
  select(event: Event): void {
    const btn = event.currentTarget as HTMLElement

    if (btn.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
      return
    }

    const key = btn.dataset.tabsKeyParam
    if (!key) return

    this.activateTab(key)

    if (this.novelIdValue > 0) {
      sessionStorage.setItem(this.storageKey, key)
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  private onFrameLoad(event: Event): void {
    const frame = event.target as HTMLElement
    if (frame.id !== "chapters-table") return

    // Turbo only replaces inner content on frame navigation — the frame element's
    // own attributes are never updated. Read the count from inside the frame.
    const countEl = frame.querySelector<HTMLElement>("[data-translated-count]")
    const count = countEl ? parseInt(countEl.dataset.translatedCount ?? "0", 10) : 0

    if (count > 0 && count > this.lastTranslatedCount) {
      const reviewFrame = document.getElementById("tab-panel-review") as any
      if (reviewFrame) {
        const src = reviewFrame.getAttribute("data-tabs-src-value")
        if (src) {
          reviewFrame.src = null
          reviewFrame.src = src
        }
      }
    }

    this.lastTranslatedCount = count
  }

  private activateTab(key: string): void {
    // Deactivate all tab buttons
    this.allTabButtons().forEach(btn => {
      btn.classList.remove("novel-tab--active")
      btn.setAttribute("aria-selected", "false")
    })

    // Activate the target button
    const targetBtn = this.tabButtonFor(key)
    if (targetBtn) {
      targetBtn.classList.add("novel-tab--active")
      targetBtn.setAttribute("aria-selected", "true")
    }

    // Show only the active panel; hide all others.
    this.allPanelFrames().forEach(frame => {
      const frameKey = frame.id.replace("tab-panel-", "")
      if (frameKey === key) {
        frame.removeAttribute("hidden")
      } else {
        frame.setAttribute("hidden", "")
      }
    })
  }

  private allTabButtons(): HTMLElement[] {
    return Array.from(
      this.element.querySelectorAll<HTMLElement>("[data-tabs-key-param]")
    )
  }

  private allPanelFrames(): HTMLElement[] {
    // Find all turbo-frame elements whose id starts with "tab-panel-"
    return Array.from(
      document.querySelectorAll<HTMLElement>("turbo-frame[id^='tab-panel-']")
    )
  }

  private tabButtonFor(key: string): HTMLElement | null {
    return this.element.querySelector<HTMLElement>(
      `[data-tabs-key-param='${key}']`
    )
  }
}
