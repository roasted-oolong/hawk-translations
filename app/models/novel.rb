class Novel < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :organization
  belongs_to :series,   optional: true
  belongs_to :poc_user, class_name: "User", optional: true

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
