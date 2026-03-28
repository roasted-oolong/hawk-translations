import { Controller } from "@hotwired/stimulus"

// upload_review_controller.ts
//
// Manages the unified chapter upload form.
//
// Responsibilities:
//   1. Listen for file select / drop events
//   2. For each file, read the first 4096 chars via FileReader to detect language
//      (Hangul ratio — same algorithm as ChapterFileClassifier on the server)
//   3. Extract chapter number from filename (same two patterns as the server)
//   4. Render a review row per file: filename, language badge, number input, remove button
//   5. Validate that every row has a chapter number ≥ 1 before enabling submit
//   6. Keep the `input` element's FileList in sync after removes (via DataTransfer)
//
// Targets: input, dropZone, reviewTable, reviewBody, submitButton
//
// The form submits normally — no fetch, no XHR. The review table only provides
// immediate feedback. The server is the authority on language and number validity.

const SAMPLE_CHARS = 4096

function isHangul(char: string): boolean {
  const code = char.charCodeAt(0)
  return code >= 0xac00 && code <= 0xd7a3
}

function detectLanguage(sample: string): "Korean" | "English" {
  const nonAsciiNonSpace = Array.from(sample).filter(
    (c) => c.charCodeAt(0) > 127 && c.trim() !== ""
  )
  if (nonAsciiNonSpace.length === 0) return "English"
  const hangulCount = nonAsciiNonSpace.filter(isHangul).length
  return hangulCount / nonAsciiNonSpace.length > 0.5 ? "Korean" : "English"
}

function extractChapterNumber(filename: string): number | null {
  const base = filename.replace(/\.[^.]+$/, "") // strip extension
  const hwa = base.match(/(\d+)화/)
  if (hwa) return parseInt(hwa[1], 10)
  const chapter = base.match(/^Chapter\s+(\d+)/i)
  if (chapter) return parseInt(chapter[1], 10)
  return null
}

interface FileRow {
  file: File
  language: "Korean" | "English"
  chapterNumber: number | null
}

export default class UploadReviewController extends Controller {
  static override targets = ["input", "dropZone", "reviewTable", "reviewBody", "submitButton"]

  declare readonly inputTarget: HTMLInputElement
  declare readonly dropZoneTarget: HTMLElement
  declare readonly reviewTableTarget: HTMLElement
  declare readonly reviewBodyTarget: HTMLElement
  declare readonly submitButtonTarget: HTMLButtonElement

  // Internal list of files and their classifications.
  private rows: FileRow[] = []

  // Document-level drop prevention (same pattern as file_upload_controller).
  private _preventDocumentDrop: (e: DragEvent) => void = () => undefined

  override connect(): void {
    this._preventDocumentDrop = (e: DragEvent) => e.preventDefault()
    document.addEventListener("dragover", this._preventDocumentDrop)
    document.addEventListener("drop", this._preventDocumentDrop)
  }

  override disconnect(): void {
    document.removeEventListener("dragover", this._preventDocumentDrop)
    document.removeEventListener("drop", this._preventDocumentDrop)
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
    const btn = event.currentTarget as HTMLElement
    const index = parseInt(btn.dataset.rowIndex ?? "-1", 10)
    if (index < 0 || index >= this.rows.length) return

    this.rows.splice(index, 1)
    this.syncInputFiles()
    this.renderRows()
    this.updateSubmitButton()
  }

  onNumberChange(event: Event): void {
    const input = event.currentTarget as HTMLInputElement
    const index = parseInt(input.dataset.rowIndex ?? "-1", 10)
    if (index < 0 || index >= this.rows.length) return

    const value = parseInt(input.value, 10)
    this.rows[index].chapterNumber = isNaN(value) || value < 1 ? null : value
    this.updateSubmitButton()
  }

  // -------------------------------------------------------------------------
  // Core logic
  // -------------------------------------------------------------------------

  private addFiles(files: File[]): void {
    // Read each file asynchronously; render once all reads are complete.
    const reads = files.map((file) => this.classifyFile(file))
    Promise.all(reads).then((newRows) => {
      this.rows.push(...newRows)
      this.syncInputFiles()
      this.renderRows()
      this.updateSubmitButton()
    })
  }

  private classifyFile(file: File): Promise<FileRow> {
    return new Promise((resolve) => {
      const reader = new FileReader()
      reader.onload = (e) => {
        const sample = ((e.target?.result as string) ?? "").slice(0, SAMPLE_CHARS)
        resolve({
          file,
          language:      detectLanguage(sample),
          chapterNumber: extractChapterNumber(file.name),
        })
      }
      reader.onerror = () => {
        // If the file can't be read, default to English with no number.
        resolve({ file, language: "English", chapterNumber: null })
      }
      reader.readAsText(file)
    })
  }

  private renderRows(): void {
    if (this.rows.length === 0) {
      this.reviewTableTarget.hidden = true
      this.reviewBodyTarget.innerHTML = ""
      return
    }

    this.reviewTableTarget.hidden = false
    this.reviewBodyTarget.innerHTML = this.rows.map((row, i) => this.rowHTML(row, i)).join("")
  }

  private rowHTML(row: FileRow, index: number): string {
    const langClass  = row.language === "Korean"
      ? "upload-language-badge--korean"
      : "upload-language-badge--english"
    const numberVal  = row.chapterNumber ?? ""
    const inputName  = `chapter[numbers][${row.file.name}]`

    return `
      <tr class="data-table__row" data-testid="upload-review-row">
        <td class="data-table__td">${escapeHTML(row.file.name)}</td>
        <td class="data-table__td">
          <span class="upload-language-badge ${langClass}" data-testid="upload-language-badge">
            ${row.language}
          </span>
        </td>
        <td class="data-table__td">
          <input
            type="number"
            name="${inputName}"
            value="${numberVal}"
            min="1"
            class="form-input upload-review__number-input"
            data-testid="upload-number-input"
            data-row-index="${index}"
            data-action="input->upload-review#onNumberChange"
          >
        </td>
        <td class="data-table__td">
          <button
            type="button"
            class="btn btn--ghost btn--sm"
            data-testid="upload-remove-btn"
            data-row-index="${index}"
            data-action="click->upload-review#onRemove"
          >Remove</button>
        </td>
      </tr>
    `
  }

  private updateSubmitButton(): void {
    const count = this.rows.length
    if (count === 0) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.textContent = "Upload"
      return
    }

    const allHaveNumbers = this.rows.every((r) => r.chapterNumber !== null)
    this.submitButtonTarget.disabled = !allHaveNumbers
    this.submitButtonTarget.textContent = `Upload ${count} file${count === 1 ? "" : "s"}`
  }

  // Rebuilds the input's FileList from the current `rows` array.
  // Required after a remove so the form submission only includes retained files.
  private syncInputFiles(): void {
    const dt = new DataTransfer()
    this.rows.forEach((row) => dt.items.add(row.file))
    this.inputTarget.files = dt.files
  }
}

function escapeHTML(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
