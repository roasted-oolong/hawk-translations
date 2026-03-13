class Team < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :organization
  has_many   :memberships,            dependent: :destroy
  has_many   :users,                  through: :memberships
  has_many   :novel_team_assignments, dependent: :destroy
  has_many   :novels,                 through: :novel_team_assignments

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :name, presence: true
end
