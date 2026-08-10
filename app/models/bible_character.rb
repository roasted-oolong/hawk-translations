# frozen_string_literal: true

class BibleCharacter < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Concerns
  # ---------------------------------------------------------------------------
  include Embeddable
  include BibleDocSynced

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------
  before_save :set_last_updated_at

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :name, presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :by_name, -> { order(:name) }

  # ---------------------------------------------------------------------------
  # Embeddable implementation
  #
  # Concatenates all semantically meaningful fields into a single string for
  # Voyage AI embedding. Korean fields (korean_name, honorifics, speech pattern
  # examples) are included — Voyage voyage-3-lite handles multilingual text
  # well, and Korean content appears throughout multiple fields, not just
  # korean_name.
  # ---------------------------------------------------------------------------
  def embeddable_text
    [
      name,
      korean_name,
      aliases,
      role,
      significance,
      physical_description,
      speech_pattern,
      honorifics_used_toward,
      honorifics_they_use,
      relationships,
      notes
    ].compact.reject(&:blank?).join(" ")
  end

  # ---------------------------------------------------------------------------
  # BibleDocSynced implementation
  # ---------------------------------------------------------------------------
  def bible_doc_category
    :characters
  end

  private

  def set_last_updated_at
    self.last_updated_at = Time.current
  end
end
