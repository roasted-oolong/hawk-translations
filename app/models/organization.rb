class Organization < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  has_many :teams,  dependent: :destroy
  has_many :series, dependent: :destroy
  has_many :novels, dependent: :destroy

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :name, presence: true
end
