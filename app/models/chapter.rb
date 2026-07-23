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
  # swap its Files card live when OcrChapterJob finishes, instead of showing a
  # static "Not uploaded" state indistinguishable from nothing having happened
  # yet. Same pattern as TranslationJob#broadcast_status_change.
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  private

  def broadcast_status_change
    broadcast_replace_later_to(
      "chapter_#{id}",
      target:  "chapter-files-#{id}",
      partial: "chapters/files_card",
      locals:  { chapter: self }
    )
  end
end
