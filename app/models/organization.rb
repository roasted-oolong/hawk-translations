class Organization < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  has_many :teams,       dependent: :destroy
  has_many :series,      dependent: :destroy
  has_many :novels,      dependent: :destroy
  has_many :memberships, through: :teams
  has_many :members,     through: :memberships, source: :user

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :name, presence: true
end
