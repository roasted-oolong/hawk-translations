class DashboardController < ApplicationController
  def index
    # Find all teams the current user belongs to, then load the novels
    # assigned to those teams — respecting the NovelTeamAssignment join.
    # No shortcut for any user, including the solo MVP user.
    team_ids = current_user.memberships.pluck(:team_id)

    novel_ids = NovelTeamAssignment
      .where(team_id: team_ids)
      .pluck(:novel_id)
      .uniq

    @novels = Novel
      .where(id: novel_ids)
      .includes(:series, chapters: [], translation_jobs: [])
      .with_attached_cover_art
      .order(:title)
  end
end
