class NovelsController < ApplicationController
  before_action :set_novel, only: [ :show, :edit, :update, :destroy ]

  def index
    @novels = Novel
      .includes(:series, chapters: [], translation_jobs: [])
      .order(:title)
  end

  def show
    @chapters = @novel.chapters.by_number
  end

  def new
    @novel = Novel.new
  end

  def create
    @novel = Novel.new(novel_params)
    if @novel.save
      redirect_to @novel, notice: "Novel created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @novel.update(novel_params)
      redirect_to @novel, notice: "Novel updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @novel.destroy
    redirect_to novels_path, notice: "Novel removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:id])
  end

  def novel_params
    params.require(:novel).permit(
      :title, :directory_name, :korean_title, :genre, :summary, :tone, :notes,
      :visibility, :series_id, :poc_user_id, :organization_id
    )
  end
end
