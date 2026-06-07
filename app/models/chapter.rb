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
    untranslated:  "untranslated",
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
end
