class User < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  has_many :memberships, dependent: :destroy
  has_many :teams,       through: :memberships
  has_many :translation_jobs

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :email,    presence: true, uniqueness: { case_sensitive: false }
  validates :name,     presence: true
  validates :provider, presence: true
  validates :uid,      presence: true, uniqueness: { scope: :provider }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Find or create a user from an OmniAuth auth hash.
  # Updates name on every sign-in to reflect any changes in the provider profile.
  def self.from_omniauth(auth)
    find_or_initialize_by(provider: auth.provider, uid: auth.uid).tap do |user|
      user.email = auth.info.email
      user.name  = auth.info.name
      user.save!
    end
  end
end
