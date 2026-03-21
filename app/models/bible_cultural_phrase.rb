# frozen_string_literal: true

class BibleCulturalPhrase < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Concerns
  # ---------------------------------------------------------------------------
  include Embeddable

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
  validates :phrase, presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :by_phrase, -> { order(:phrase) }

  # ---------------------------------------------------------------------------
  # Embeddable implementation
  # ---------------------------------------------------------------------------
  def embeddable_text
    [
      phrase,
      korean_phrase,
      literal_translation,
      intended_meaning,
      context,
      established_translation,
      notes
    ].compact.reject(&:blank?).join(" ")
  end

  private

  def set_last_updated_at
    self.last_updated_at = Time.current
  end
end
