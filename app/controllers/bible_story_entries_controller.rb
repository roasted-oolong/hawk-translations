class BibleStoryEntriesController < ApplicationController
  PREREAD_CATEGORY = :story

  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]
  include BiblePrereadDismissed

  def index
    # Group by category for display; within each group, order by title
    @entries_by_category = BibleStoryEntry.categories.keys.index_with do |cat|
      @novel.bible_story_entries.by_category(cat).by_title
    end
  end

  def show; end

  def new
    @entry = @novel.bible_story_entries.build
    @entry.title = params[:prefill_name] if params[:prefill_name].present?
  end

  def create
    @entry = @novel.bible_story_entries.build(entry_params)
    respond_to do |format|
      if @entry.save
        format.html { redirect_to edit_novel_bible_story_entry_path(@novel, @entry), notice: "Story entry added. Fill in the details below." }
        format.json { render json: { id: @entry.id, display_name: @entry.title, edit_url: edit_novel_bible_story_entry_path(@novel, @entry) }, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    respond_to do |format|
      if @entry.update(entry_params)
        format.html { redirect_to novel_bible_story_entry_path(@novel, @entry), notice: "Story entry updated." }
        format.json { render json: { id: @entry.id, display_name: @entry.title }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity }
      end
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
