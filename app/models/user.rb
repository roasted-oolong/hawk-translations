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
  # Instance methods
  # ---------------------------------------------------------------------------

  # Returns the most privileged role label for display purposes.
  # Hierarchy: platform_admin > team_admin > team_member > (none)
  def display_role
    return "Platform Admin" if platform_admin?
    return "Team Admin"     if memberships.any?(&:team_admin?)
    return "Team Member"    if memberships.any?(&:team_member?)

    "No role assigned"
  end

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
