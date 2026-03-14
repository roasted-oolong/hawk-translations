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

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :visibility, { discoverable: "discoverable", hidden: "hidden" }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :title,      presence: true
  validates :visibility, presence: true
end
