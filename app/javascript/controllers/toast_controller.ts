// toast_controller.ts
//
// Stimulus controller for toast notifications. Toasts appear from the
// bottom-right corner of the screen, auto-dismiss after a configurable
// duration, and stack if multiple fire simultaneously.
//
// Intended to be triggered via Turbo Streams on job completion:
//   <%= turbo_stream.append "toast-region" do %>
//     <div data-controller="toast" data-toast-duration-value="4000"
//          data-toast-type-value="success">
//       Job completed successfully.
//     </div>
//   <% end %>
//
// The #toast-region div is rendered once in the application layout.
// Each stream append creates a new toast element; the controller mounts on
// connect, animates in, then removes itself after the duration.
//
// data-toast-duration-value — auto-dismiss delay in ms (default: 4000)
// data-toast-type-value     — "success" | "error" | "info" (default: "info")

import { Controller } from "@hotwired/stimulus"

const TYPE_CLASSES: Record<string, string> = {
  success: "toast--success",
  error:   "toast--error",
  info:    "toast--info",
}

export default class ToastController extends Controller {
  static values = {
    duration: { type: Number,  default: 4000 },
    type:     { type: String,  default: "info" },
  }

  declare durationValue: number
  declare typeValue:     string

  private dismissTimer: ReturnType<typeof setTimeout> | null = null

  connect(): void {
    // Apply the type modifier class.
    const modifier = TYPE_CLASSES[this.typeValue] ?? TYPE_CLASSES["info"]
    this.element.classList.add("toast", modifier)

    // Trigger the enter animation on the next frame so the initial state
    // is painted before the transition begins.
    requestAnimationFrame(() => {
      this.element.classList.add("toast--visible")
    })

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
    this.element.classList.remove("toast--visible")
    this.element.classList.add("toast--dismissing")

    this.element.addEventListener(
      "transitionend",
      () => this.element.remove(),
      { once: true }
    )

    // Fallback if transitionend doesn't fire (prefers-reduced-motion).
    setTimeout(() => {
      if (this.element.isConnected) this.element.remove()
    }, 300)
  }
}
