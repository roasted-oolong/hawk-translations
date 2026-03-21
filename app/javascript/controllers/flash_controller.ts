// flash_controller.ts
//
// Stimulus controller for flash message auto-dismiss and manual dismiss.
//
// Usage (in _flash.html.erb):
//   data-controller="flash"
//   data-flash-duration-value="4000"     ← auto-dismiss after 4s (notices only)
//   data-action="click->flash#dismiss"   ← on dismiss button
//
// Alerts (errors) never auto-dismiss — the user must explicitly close them.
// Duration value is optional; omitting it disables auto-dismiss.

import { Controller } from "@hotwired/stimulus"

export default class FlashController extends Controller {
  static values = {
    duration: { type: Number, default: 0 },
  }

  declare durationValue: number
  private dismissTimer: ReturnType<typeof setTimeout> | null = null

  connect(): void {
    if (this.durationValue > 0) {
      this.dismissTimer = setTimeout(() => this.dismiss(), this.durationValue)
    }
  }

  disconnect(): void {
    if (this.dismissTimer !== null) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = null
    }
  }

  dismiss(): void {
    this.element.classList.add("flash-message--dismissing")

    // Wait for the CSS opacity transition to finish, then remove the element.
    this.element.addEventListener(
      "transitionend",
      () => this.element.remove(),
      { once: true }
    )

    // Fallback: if transitionend never fires (e.g. prefers-reduced-motion),
    // remove after a short timeout.
    setTimeout(() => this.element.remove(), 300)
  }
}
