# frozen_string_literal: true

# =============================================================================
# ProvisionWorkspace
#
# Idempotent service that creates the solo-translator workspace on first
# sign-in: one Organization (named after the user), one default Team inside
# it, and a team_admin Membership joining the user to that team.
#
# Called from SessionsController#create immediately after a new user record
# is persisted. Idempotency guard: if the user already has any membership,
# the service is a no-op and returns the user unchanged.
#
# Usage:
#   ProvisionWorkspace.call(user)
# =============================================================================
class ProvisionWorkspace
  def self.call(user)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  def call
    return @user if @user.memberships.exists?

    ActiveRecord::Base.transaction do
      org  = Organization.create!(name: @user.name)
      team = org.teams.create!(name: "Default Team")
      team.memberships.create!(user: @user, role: "team_admin")
    end

    @user
  end
end
