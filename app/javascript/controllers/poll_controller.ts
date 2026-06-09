// poll_controller.ts
//
// Stimulus controller for Turbo Frame interval polling.
//
// Mounts on a wrapper element that contains a <turbo-frame>. On each tick,
// sets frame.src = null then frame.src = url, forcing Turbo to re-fetch the
// URL and swap the matching frame content in place — no full page reload.
//
// Requires data-poll-url-value pointing to the URL that renders the frame,
// which may differ from window.location.href when the frame lives inside a
// tab panel loaded from a different path.
//
// The wrapper is only rendered server-side when the job is active (queued or
// running). Once the job reaches a terminal state, the server omits the
// wrapper, so the controller is never mounted and polling stops automatically.
//
// Note: frame.reload() is a no-op for inline-rendered frames (no src
// attribute), so we drive the fetch manually via the src setter instead.

import { Controller } from "@hotwired/stimulus"

export default class PollController extends Controller {
  static values = {
    interval: { type: Number, default: 3000 },
    url:      { type: String, default: "" },
  }

  declare intervalValue: number
  declare urlValue: string
  private pollTimer: ReturnType<typeof setInterval> | null = null

  connect(): void {
    const frame = this.element.querySelector("turbo-frame")
    if (!frame) return

    const url = this.urlValue || window.location.href

    this.pollTimer = setInterval(() => {
      ;(frame as any).src = null
      ;(frame as any).src = url
    }, this.intervalValue)
  }

  disconnect(): void {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }
}
