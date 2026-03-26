# frozen_string_literal: true

# =============================================================================
# AutoAssignNovel
#
# Creates a NovelTeamAssignment at permission_level: "translator" between a
# newly-created novel and the user's first team. Called from NovelsController
# immediately after a novel is saved for the first time.
#
# Idempotency guard: if a NovelTeamAssignment already exists for that
# (novel, team) pair the upsert is skipped and the novel is returned as-is.
# No-op if the user has no teams (safe for future states where a user might
# exist without a provisioned workspace).
#
# MVP note: uses `user.teams.first` as the target team. When multi-team users
# exist, assignment target will need to be explicit. See DECISIONS.md.
#
# Usage:
#   AutoAssignNovel.call(novel, user)
# =============================================================================
class AutoAssignNovel
  def self.call(novel, user)
    new(novel, user).call
  end

  def initialize(novel, user)
    @novel = novel
    @user  = user
  end

  def call
    team = @user.teams.first
    return @novel if team.nil?

    NovelTeamAssignment.find_or_create_by!(novel: @novel, team: team) do |a|
      a.permission_level = "translator"
    end

    @novel
  end
end
