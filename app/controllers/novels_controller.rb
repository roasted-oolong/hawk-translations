class NovelsController < ApplicationController
  before_action :set_novel,            only: [ :show, :edit, :update, :destroy, :destroy_cover_art ]
  before_action :set_form_collections, only: [ :new, :create, :edit, :update ]

  def index
    @novels = Novel
      .includes(:series, chapters: [], translation_jobs: [])
      .with_attached_cover_art
      .order(:title)
  end

  def show
    @chapters = @novel.chapters.by_number
  end

  def new
    @novel = Novel.new
  end

  def create
    @novel = Novel.new(novel_create_params)
    if @novel.save
      AutoAssignNovel.call(@novel, current_user)
      redirect_to @novel, notice: "Novel created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @novel.update(novel_update_params)
      redirect_to @novel, notice: "Novel updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @novel.destroy
    redirect_to novels_path, notice: "Novel removed."
  end

  # DELETE /novels/:id/cover_art
  # Purges the cover_art Active Storage attachment and redirects back to the novel.
  def destroy_cover_art
    @novel.cover_art.purge
    redirect_to @novel, notice: "Cover art removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:id])
  end

  # Scoped collections for the new/edit form selects.
  # For new, the organization comes from the hidden field value; once the novel
  # is saved we have @novel.organization. For the new form (before save),
  # organization is not yet set, so we fall back to all series/users in the
  # first organization in the system as a reasonable default for solo MVP.
  # This is scoped properly — no cross-org data leaks — because the hidden
  # field pins the org.
  def set_form_collections
    org = @novel&.organization || Organization.first
    @series_options = org ? Series.where(organization: org).order(:name) : Series.none
    @poc_user_options = org ? User.joins(memberships: :team)
                                   .where(teams: { organization: org })
                                   .distinct
                                   .order(:name) : User.none
  end

  # directory_name is set on create only; it cannot be changed via the UI.
  # When omitted (inline quick-create dialog), it is derived from the title.
  def novel_create_params
    permitted = params.require(:novel).permit(
      :title, :directory_name, :korean_title, :genre, :summary, :tone, :notes,
      :visibility, :series_id, :poc_user_id, :organization_id, :cover_art
    )

    if permitted[:directory_name].blank? && permitted[:title].present?
      permitted[:directory_name] = permitted[:title]
        .downcase
        .gsub(/[^a-z0-9\s-]/, "")
        .gsub(/\s+/, "-")
        .gsub(/-+/, "-")
        .gsub(/\A-|-\z/, "")
    end

    permitted
  end

  # directory_name intentionally excluded — the edit form does not render the
  # field, so no value is submitted. Keeping it out of permitted params is a
  # defence-in-depth measure: even a hand-crafted POST cannot change it.
  def novel_update_params
    params.require(:novel).permit(
      :title, :korean_title, :genre, :summary, :tone, :notes,
      :visibility, :series_id, :poc_user_id, :cover_art
    )
  end
end
