import { Controller } from "@hotwired/stimulus"

export default class ChapterViewerController extends Controller<HTMLElement> {
  static values = { saveUrl: String }

  static targets = [
    "editableText",
    "chapterCard",
    "compareBtn",
    "paneText",
    "koreanPane",
    "savedIndicator",
  ]

  declare saveUrlValue: string
  declare editableTextTarget: HTMLTextAreaElement
  declare chapterCardTarget: HTMLElement
  declare compareBtnTarget: HTMLButtonElement
  declare paneTextTarget: HTMLTextAreaElement
  declare koreanPaneTarget: HTMLElement
  declare savedIndicatorTarget: HTMLElement

  private compareActive = false
  private lastScrollTop = 0
  private scrollHandler: (() => void) | null = null

  private handleKeydown = (event: KeyboardEvent) => {
    if ((event.ctrlKey || event.metaKey) && event.key === 's') {
      event.preventDefault()
      this.saveText()
    }
  }

  connect() {
    this.resizeTextarea()
    document.addEventListener('keydown', this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown)
    this.detachScrollSync()
  }

  toggleKorean() {
    this.compareActive = !this.compareActive
    this.compareBtnTarget.classList.toggle("chapter-review__compare-btn--active", this.compareActive)
    this.chapterCardTarget.classList.toggle("chapter-review__chapter-card--compare", this.compareActive)

    const container = this.element.closest<HTMLElement>(".container")
    container?.classList.toggle("container--wide", this.compareActive)

    if (this.compareActive) {
      this.paneTextTarget.value = this.editableTextTarget.value
      this.paneTextTarget.style.height = "auto"
      this.paneTextTarget.style.height = `${this.paneTextTarget.scrollHeight}px`
      this.attachScrollSync()
    } else {
      this.editableTextTarget.value = this.paneTextTarget.value
      this.detachScrollSync()
      this.resizeTextarea()
    }
  }

  autoResize(event: Event) {
    const textarea = event.target as HTMLTextAreaElement
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
  }

  autoResizePane(event: Event) {
    const textarea = event.target as HTMLTextAreaElement
    textarea.style.height = "auto"
    textarea.style.height = `${textarea.scrollHeight}px`
  }

  saveText() {
    if (this.compareActive) {
      this.editableTextTarget.value = this.paneTextTarget.value
    }

    fetch(this.saveUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": this.csrfToken(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ text: this.editableTextTarget.value }),
    }).then(() => this.flashSaved())
  }

  private attachScrollSync() {
    this.lastScrollTop = window.scrollY
    this.scrollHandler = () => {
      const delta = window.scrollY - this.lastScrollTop
      this.lastScrollTop = window.scrollY
      this.koreanPaneTarget.scrollTop += delta
    }
    window.addEventListener("scroll", this.scrollHandler)
  }

  private detachScrollSync() {
    if (this.scrollHandler) {
      window.removeEventListener("scroll", this.scrollHandler)
      this.scrollHandler = null
    }
  }

  private resizeTextarea() {
    this.editableTextTarget.style.height = "auto"
    this.editableTextTarget.style.height = `${this.editableTextTarget.scrollHeight}px`
  }

  private flashSaved() {
    this.savedIndicatorTarget.hidden = false
    setTimeout(() => { this.savedIndicatorTarget.hidden = true }, 2000)
  }

  private csrfToken(): string {
    return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
  }
}
