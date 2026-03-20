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
  has_many :bible_story_entries,    dependent: :destroy

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
end
