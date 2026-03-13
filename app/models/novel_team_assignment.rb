class NovelTeamAssignment < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel
  belongs_to :team

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :permission_level, {
    viewer:     "viewer",
    editor:     "editor",
    translator: "translator",
    admin:      "admin"
  }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :permission_level, presence: true
  validates :novel_id, uniqueness: { scope: :team_id }
end
