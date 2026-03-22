import { Controller } from "@hotwired/stimulus"

export default class FileUploadController extends Controller {
  static override targets = ["input", "zone", "preview", "submit"]

  declare readonly inputTarget: HTMLInputElement
  declare readonly zoneTarget: HTMLElement
  declare readonly previewTarget: HTMLElement
  declare readonly submitTarget: HTMLButtonElement
  declare readonly hasSubmitTarget: boolean

  // Bound reference kept as an instance property so connect/disconnect use
  // the same function identity. Initialized to a no-op so the type is always
  // defined — no definite-assignment assertion (!) needed.
  private _preventDocumentDrop: (e: DragEvent) => void = () => undefined

  override connect(): void {
    // Prevent the browser from opening dropped files at the document level.
    // Without this, a miss-drop outside the zone navigates away from the page.
    this._preventDocumentDrop = (e: DragEvent) => e.preventDefault()
    document.addEventListener("dragover", this._preventDocumentDrop)
    document.addEventListener("drop", this._preventDocumentDrop)

    this.updatePreview()
  }

  override disconnect(): void {
    document.removeEventListener("dragover", this._preventDocumentDrop)
    document.removeEventListener("drop", this._preventDocumentDrop)
  }

  // Triggered by click on the label wrapping the hidden input — no JS needed
  // for the click path. This method is kept for any programmatic callers.
  open(): void {
    this.inputTarget.click()
  }

  onChange(): void {
    this.updatePreview()
  }

  onDragOver(event: DragEvent): void {
    event.preventDefault()
    this.zoneTarget.classList.add("file-upload--dragging")
  }

  onDragLeave(event: DragEvent): void {
    // Only remove the class when leaving the zone entirely, not when
    // moving between child elements inside it.
    // relatedTarget is EventTarget | null; contains() accepts Node | null,
    // and every EventTarget that can be inside a DOM zone is also a Node.
    if (!this.zoneTarget.contains(event.relatedTarget as Node | null)) {
      this.zoneTarget.classList.remove("file-upload--dragging")
    }
  }

  onDrop(event: DragEvent): void {
    event.preventDefault()
    this.zoneTarget.classList.remove("file-upload--dragging")

    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return

    // DataTransfer constructor is a browser API — always available here, but
    // the explicit cast quiets strict-lib complaints about the constructor
    // signature not being callable in some TypeScript / DOM-lib combinations.
    const dt = new DataTransfer()
    Array.from(files).forEach((f: File) => dt.items.add(f))
    this.inputTarget.files = dt.files

    this.updatePreview()
  }

  private updatePreview(): void {
    const files = this.inputTarget.files
    if (!files || files.length === 0) {
      this.previewTarget.classList.add("file-upload__preview--empty")
      this.previewTarget.textContent = ""
      if (this.hasSubmitTarget) this.submitTarget.disabled = true
      return
    }

    this.previewTarget.classList.remove("file-upload__preview--empty")
    this.previewTarget.innerHTML = Array.from(files)
      .map(f => `<span class="file-upload__filename">${f.name}</span>`)
      .join("")

    if (this.hasSubmitTarget) this.submitTarget.disabled = false
  }
}