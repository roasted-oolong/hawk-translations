# frozen_string_literal: true

class BibleStoryEntry < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Concerns
  # ---------------------------------------------------------------------------
  include Embeddable

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :category, {
    main_plot:      "main_plot",
    subplot:        "subplot",
    watch_list:     "watch_list",
    theme:          "theme",
    world_building: "world_building"
  }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------
  before_save :set_last_updated_at

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :title,    presence: true
  validates :category, presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :by_title,    -> { order(:title) }
  scope :by_category, ->(cat) { where(category: cat) }

  # ---------------------------------------------------------------------------
  # Embeddable implementation
  #
  # category is included as a string so semantic queries for e.g. "main plot
  # arc" can match on the category value as well as title/content.
  # ---------------------------------------------------------------------------
  def embeddable_text
    [
      category,
      title,
      content,
      notes
    ].compact.reject(&:blank?).join(" ")
  end

  private

  def set_last_updated_at
    self.last_updated_at = Time.current
  end
end
