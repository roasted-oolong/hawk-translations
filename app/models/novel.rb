class Novel < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :organization
  belongs_to :series,   optional: true
  belongs_to :poc_user, class_name: "User", optional: true

  has_many :novel_team_assignments, dependent: :destroy
  has_many :teams, through: :novel_team_assignments
  has_many :chapters, dependent: :destroy
  has_many :translation_jobs, dependent: :destroy

  # Bible entry tables — each category is its own table
  has_many :bible_characters,       dependent: :destroy
  has_many :bible_locations,        dependent: :destroy
  has_many :bible_terminologies,    dependent: :destroy
  has_many :bible_cultural_phrases, dependent: :destroy
  has_many :bible_story_entries,         dependent: :destroy
  has_many :voice_calibration_passages,  dependent: :destroy

  # Cover art — optional, single image attachment
  has_one_attached :cover_art

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :visibility, { discoverable: "discoverable", hidden: "hidden" }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :title,          presence: true
  validates :visibility,     presence: true
  validates :directory_name, presence: true
  validates :directory_name, uniqueness: { scope: :organization_id,
                               message: "is already used by another novel in this organization" }

  validate :cover_art_content_type, if: -> { cover_art.attached? }
  validate :cover_art_size,         if: -> { cover_art.attached? }

  private

  COVER_ART_ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze

  def cover_art_content_type
    unless cover_art.content_type.in?(COVER_ART_ALLOWED_TYPES)
      errors.add(:cover_art, "must be a JPEG, PNG, or WebP image")
    end
  end

  def cover_art_size
    if cover_art.byte_size > 5.megabytes
      errors.add(:cover_art, "must be smaller than 5MB")
    end
  end
end
