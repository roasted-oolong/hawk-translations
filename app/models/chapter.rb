class Chapter < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel

  has_one_attached :korean_source
  has_one_attached :translated_output

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :status, {
    ocr_processing: "ocr_processing",
    untranslated:  "untranslated",
    ocr_failed:    "ocr_failed",
    prereading:    "prereading",
    preread_failed: "preread_failed",
    preread:       "preread",
    translated:    "translated",
    reviewed:      "reviewed"
  }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :number, presence: true,
                     numericality: { only_integer: true, greater_than: 0 },
                     uniqueness: { scope: :novel_id }
  validates :status, presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :by_number, -> { order(:number) }

  # ---------------------------------------------------------------------------
  # Broadcasts
  # ---------------------------------------------------------------------------
  # Lets the chapter show page (subscribed via turbo_stream_from "chapter_#{id}")
  # swap its Files card and Korean pane live when OcrChapterJob finishes,
  # instead of showing stale/empty state until the user manually refreshes.
  # Same pattern as TranslationJob#broadcast_status_change. Keyed off status
  # rather than the korean_source attachment directly (Active Storage
  # attachment changes don't fire Chapter's own update callbacks) — every
  # place that attaches korean_source also updates status in the same beat.
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # FormatKoreanChapterJob re-attaches a cleaned korean_source without
  # changing status (it's already "untranslated" from OcrChapterJob), so
  # that update wouldn't trip the after_update_commit above — called
  # directly instead, right after the cleaned attachment is saved.
  def broadcast_korean_pane
    broadcast_replace_later_to(
      "chapter_#{id}",
      target:  "chapter-korean-pane-#{id}",
      partial: "chapters/korean_pane",
      locals:  { chapter: self }
    )
  end

  private

  def broadcast_status_change
    broadcast_replace_later_to(
      "chapter_#{id}",
      target:  "chapter-files-#{id}",
      partial: "chapters/files_card",
      locals:  { chapter: self }
    )
    broadcast_korean_pane
  end
end
