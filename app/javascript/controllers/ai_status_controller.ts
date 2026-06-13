import { Controller } from "@hotwired/stimulus"

// Polls /ai_status every 30 seconds and reflects the result as data-status on
// the controller element. CSS uses data-status to colour the indicator dot.
//
// Targets:
//   label — text node updated with a human-readable state string
export default class AiStatusController extends Controller {
  static targets = ["label"]

  declare readonly labelTarget: HTMLElement

  private intervalId: ReturnType<typeof setInterval> | null = null

  connect(): void {
    this.check()
    this.intervalId = setInterval(() => this.check(), 30_000)
  }

  disconnect(): void {
    if (this.intervalId !== null) clearInterval(this.intervalId)
  }

  private async check(): Promise<void> {
    try {
      const res = await fetch("/ai_status", { headers: { Accept: "application/json" } })
      const { status } = await res.json()
      this.update(status as string)
    } catch {
      this.update("unavailable")
    }
  }

  private update(status: string): void {
    this.element.setAttribute("data-status", status)
    const labels: Record<string, string> = {
      ok:          "AI ready",
      loading:     "AI loading",
      unavailable: "AI offline",
    }
    this.labelTarget.textContent = labels[status] ?? "AI unknown"
  }
}
