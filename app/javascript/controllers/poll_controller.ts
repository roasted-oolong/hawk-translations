// poll_controller.ts
//
// Stimulus controller for Turbo Frame interval polling.
//
// Mounts on a wrapper element that contains a <turbo-frame>. Calls
// frame.reload() on a configurable interval so the frame re-fetches the
// current page and updates its content in place — no full page reload.
//
// Usage (in translation_jobs/show.html.erb):
//   <div data-controller="poll" data-poll-interval-value="3000">
//     <turbo-frame id="job-status">...</turbo-frame>
//   </div>
//
// The wrapper is only rendered server-side when the job is active (queued or
// running). Once the job reaches a terminal state, the server stops rendering
// the wrapper, so the controller is never mounted and polling does not start.
//
// frame.reload() re-fetches the current page URL and extracts the matching
// <turbo-frame id="job-status"> from the response. The rest of the page is
// untouched.

import { Controller } from "@hotwired/stimulus"

export default class PollController extends Controller {
  static values = {
    interval: { type: Number, default: 3000 },
  }

  declare intervalValue: number
  private pollTimer: ReturnType<typeof setInterval> | null = null

  connect(): void {
    const frame = this.element.querySelector("turbo-frame")
    if (!frame) return

    this.pollTimer = setInterval(() => {
      (frame as any).reload()
    }, this.intervalValue)
  }

  disconnect(): void {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }
}
