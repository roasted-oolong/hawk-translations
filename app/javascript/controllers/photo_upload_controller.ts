import { Controller } from "@hotwired/stimulus"

// photo_upload_controller.ts
//
// Manages the "Photo scan (OCR)" chapter upload form.
//
// Responsibilities:
//   1. Listen for file select / drop events (images, or a single PDF)
//   2. Render an ordered thumbnail list per photo (filename, preview, move
//      up/down, remove) — default order is the order files were added.
//      A PDF row gets a generic file badge instead of an image preview,
//      since an <img> can't render a PDF blob.
//   3. Keep the `input` element's FileList in sync with the row order (via
//      DataTransfer), so submitted order always matches on-screen order
//   4. Validate that at least one photo is present, the batch isn't mixing
//      a PDF with other files (or more than one PDF), and the chapter
//      number is valid, before enabling submit. This mirrors — but doesn't
//      replace — the server-side check in ChaptersController#create_from_photos;
//      it's UX sugar so a doomed submission never leaves this page.
//
// Targets: input, dropZone, thumbList, submitButton, numberInput, batchError
//
// Unlike upload_review_controller.ts, this controller does not sample file
// content or classify language/chapter-number from filenames — none of that
// applies to photos. Reordering uses move-up/move-down buttons rather than
// native HTML5 drag-and-drop, which is unreliable to simulate in headless
// browser system specs and unnecessary for a handful of photos per chapter.
//
// The form submits normally — no fetch, no XHR.

const PDF_MIME = "application/pdf"

interface PhotoRow {
  file: File
  previewUrl: string
}

export default class PhotoUploadController extends Controller {
  static override targets = ["input", "dropZone", "thumbList", "submitButton", "numberInput", "batchError"]

  declare readonly inputTarget: HTMLInputElement
  declare readonly dropZoneTarget: HTMLElement
  declare readonly thumbListTarget: HTMLElement
  declare readonly submitButtonTarget: HTMLInputElement
  declare readonly numberInputTarget: HTMLInputElement
  declare readonly batchErrorTarget: HTMLElement

  private rows: PhotoRow[] = []

  private _preventDocumentDrop: (e: DragEvent) => void = () => undefined

  override connect(): void {
    this._preventDocumentDrop = (e: DragEvent) => e.preventDefault()
    document.addEventListener("dragover", this._preventDocumentDrop)
    document.addEventListener("drop", this._preventDocumentDrop)
  }

  override disconnect(): void {
    document.removeEventListener("dragover", this._preventDocumentDrop)
    document.removeEventListener("drop", this._preventDocumentDrop)
    this.rows.forEach((row) => URL.revokeObjectURL(row.previewUrl))
  }

  // -------------------------------------------------------------------------
  // Event handlers
  // -------------------------------------------------------------------------

  onFilesChanged(): void {
    const files = Array.from(this.inputTarget.files ?? [])
    this.addFiles(files)
  }

  onDragOver(event: DragEvent): void {
    event.preventDefault()
    this.dropZoneTarget.classList.add("upload-zone--dragging")
  }

  onDragLeave(event: DragEvent): void {
    if (!this.dropZoneTarget.contains(event.relatedTarget as Node | null)) {
      this.dropZoneTarget.classList.remove("upload-zone--dragging")
    }
  }

  onDrop(event: DragEvent): void {
    event.preventDefault()
    this.dropZoneTarget.classList.remove("upload-zone--dragging")
    const files = Array.from(event.dataTransfer?.files ?? [])
    if (files.length > 0) this.addFiles(files)
  }

  onRemove(event: Event): void {
    const index = this.rowIndexFromEvent(event)
    if (index < 0) return

    URL.revokeObjectURL(this.rows[index].previewUrl)
    this.rows.splice(index, 1)
    this.syncInputFiles()
    this.renderRows()
    this.updateSubmitButton()
  }

  onMoveUp(event: Event): void {
    const index = this.rowIndexFromEvent(event)
    if (index <= 0) return

    this.swapRows(index, index - 1)
  }

  onMoveDown(event: Event): void {
    const index = this.rowIndexFromEvent(event)
    if (index < 0 || index >= this.rows.length - 1) return

    this.swapRows(index, index + 1)
  }

  onNumberChanged(): void {
    this.updateSubmitButton()
  }

  // -------------------------------------------------------------------------
  // Core logic
  // -------------------------------------------------------------------------

  private addFiles(files: File[]): void {
    const newRows = files.map((file) => ({ file, previewUrl: URL.createObjectURL(file) }))
    this.rows.push(...newRows)
    this.syncInputFiles()
    this.renderRows()
    this.updateSubmitButton()
  }

  private swapRows(a: number, b: number): void {
    ;[this.rows[a], this.rows[b]] = [this.rows[b], this.rows[a]]
    this.syncInputFiles()
    this.renderRows()
  }

  private rowIndexFromEvent(event: Event): number {
    const btn = event.currentTarget as HTMLElement
    return parseInt(btn.dataset.rowIndex ?? "-1", 10)
  }

  private renderRows(): void {
    if (this.rows.length === 0) {
      this.thumbListTarget.hidden = true
      this.thumbListTarget.innerHTML = ""
      return
    }

    this.thumbListTarget.hidden = false
    this.thumbListTarget.innerHTML = this.rows.map((row, i) => this.rowHTML(row, i)).join("")
  }

  private rowHTML(row: PhotoRow, index: number): string {
    const isFirst = index === 0
    const isLast = index === this.rows.length - 1
    const preview = isPdf(row.file)
      ? `<span class="photo-upload-row__thumb photo-upload-row__thumb--pdf" data-testid="photo-upload-pdf-badge">PDF</span>`
      : `<img class="photo-upload-row__thumb" src="${row.previewUrl}" alt="" data-testid="photo-upload-thumb">`

    return `
      <li class="photo-upload-row" data-testid="photo-upload-row">
        ${preview}
        <span class="photo-upload-row__name">${escapeHTML(row.file.name)}</span>
        <div class="photo-upload-row__actions">
          <button type="button" class="btn btn--ghost btn--sm" data-testid="photo-move-up-btn"
                  data-row-index="${index}" data-action="click->photo-upload#onMoveUp"
                  ${isFirst ? "disabled" : ""}>&uarr;</button>
          <button type="button" class="btn btn--ghost btn--sm" data-testid="photo-move-down-btn"
                  data-row-index="${index}" data-action="click->photo-upload#onMoveDown"
                  ${isLast ? "disabled" : ""}>&darr;</button>
          <button type="button" class="btn btn--ghost btn--sm" data-testid="photo-remove-btn"
                  data-row-index="${index}" data-action="click->photo-upload#onRemove">Remove</button>
        </div>
      </li>
    `
  }

  // Mirrors ChaptersController#validate_photo_batch: a batch is either a
  // single PDF, or one-or-more photos — never both, never multiple PDFs.
  private batchErrorMessage(): string | null {
    const pdfCount = this.rows.filter((row) => isPdf(row.file)).length
    if (pdfCount > 0 && this.rows.length > 1) {
      return "Upload a single PDF, or one or more photos — not both in the same upload."
    }
    return null
  }

  private updateSubmitButton(): void {
    const count = this.rows.length
    const number = parseInt(this.numberInputTarget.value, 10)
    const validNumber = !isNaN(number) && number >= 1
    const batchError = this.batchErrorMessage()

    this.batchErrorTarget.hidden = batchError === null
    this.batchErrorTarget.textContent = batchError ?? ""

    this.submitButtonTarget.disabled = count === 0 || !validNumber || batchError !== null
    // submitButtonTarget is an <input type="submit"> — its label comes from
    // `value`, not `textContent` (a void element has no rendered children).
    this.submitButtonTarget.value = count === 0
      ? "Upload"
      : count === 1 && isPdf(this.rows[0].file)
        ? "Upload PDF"
        : `Upload ${count} photo${count === 1 ? "" : "s"}`
  }

  // Rebuilds the input's FileList from the current `rows` array, in order.
  private syncInputFiles(): void {
    const dt = new DataTransfer()
    this.rows.forEach((row) => dt.items.add(row.file))
    this.inputTarget.files = dt.files
  }
}

function isPdf(file: File): boolean {
  return file.type === PDF_MIME
}

function escapeHTML(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
