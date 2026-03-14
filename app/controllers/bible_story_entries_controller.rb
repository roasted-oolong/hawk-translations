class BibleStoryEntriesController < ApplicationController
  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    # Group by category for display; within each group, order by title
    @entries_by_category = BibleStoryEntry.categories.keys.index_with do |cat|
      @novel.bible_story_entries.by_category(cat).by_title
    end
  end

  def show; end

  def new
    @entry = @novel.bible_story_entries.build
  end

  def create
    @entry = @novel.bible_story_entries.build(entry_params)
    if @entry.save
      redirect_to novel_bible_story_entry_path(@novel, @entry), notice: "Story entry added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      redirect_to novel_bible_story_entry_path(@novel, @entry), notice: "Story entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to novel_bible_story_entries_path(@novel), notice: "Story entry removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_entry
    @entry = @novel.bible_story_entries.find(params[:id])
  end

  def entry_params
    params.require(:bible_story_entry).permit(
      :category, :title, :content, :first_appearance_chapter, :notes
    )
  end
end
