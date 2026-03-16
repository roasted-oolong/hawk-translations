class BibleStoryEntry < ApplicationRecord
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

  private

  def set_last_updated_at
    self.last_updated_at = Time.current
  end
end
