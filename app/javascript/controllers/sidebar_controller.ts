// sidebar_controller.ts
//
// Mobile off-canvas sidebar toggle.
//
// DOM layout: this controller mounts on <body> (the common ancestor of both
// the sidebar <aside> and the topbar hamburger button). This is necessary
// because Stimulus targets must live inside the controller's element — the
// hamburger is in _topbar.html.erb and the sidebar is in _sidebar.html.erb,
// so neither partial alone can contain both.
//
// Responsibilities:
//   - Toggle `data-sidebar-open` on the sidebar target element ("true"/"false")
//   - Sync `aria-expanded` on the toggle target (hamburger button)
//   - Dismiss the sidebar on outside-click
//
// The controller does NOT inspect window.innerWidth. Whether the sidebar
// visually responds to data-sidebar-open is entirely the CSS's concern —
// at desktop widths the sidebar is always visible regardless of the attribute.
// The controller just manages the attribute and aria state uniformly.
//
// Targets:
//   sidebar  — the <aside data-sidebar-target="sidebar"> element
//   toggle   — the hamburger <button data-sidebar-target="toggle"> element(s)

import { Controller } from "@hotwired/stimulus"

export default class SidebarController extends Controller {
  static targets = ["sidebar", "toggle"]

  declare readonly sidebarTarget: HTMLElement
  declare readonly toggleTargets: HTMLElement[]

  // Bound reference kept for add/removeEventListener symmetry.
  private boundOutsideClick: (event: MouseEvent) => void = () => {}

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  connect(): void {
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)
  }

  disconnect(): void {
    document.removeEventListener("click", this.boundOutsideClick)
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  toggle(): void {
    const isOpen = this.sidebarTarget.getAttribute("data-sidebar-open") === "true"
    this.setOpen(!isOpen)
  }

  // ------------------------------------------------------------------
  // Private
  // ------------------------------------------------------------------

  private setOpen(open: boolean): void {
    this.sidebarTarget.setAttribute("data-sidebar-open", String(open))

    this.toggleTargets.forEach((btn) => {
      btn.setAttribute("aria-expanded", String(open))
    })
  }

  private handleOutsideClick(event: MouseEvent): void {
    const isOpen = this.sidebarTarget.getAttribute("data-sidebar-open") === "true"
    if (!isOpen) return

    const target = event.target as Node

    // Ignore clicks on (or inside) the sidebar itself.
    if (this.sidebarTarget.contains(target)) return

    // Ignore clicks on (or inside) any toggle button so that the toggle()
    // action, which fires on the same event, is not immediately undone.
    if (this.toggleTargets.some((btn) => btn.contains(target))) return

    this.setOpen(false)
  }
}
