class BibleLocationsController < ApplicationController
  PREREAD_CATEGORY = :locations

  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]
  include BiblePrereadDismissed
  include BibleEntryChapterPrefill

  def index
    @entries = @novel.bible_locations.by_name
  end

  def show; end

  def new
    @entry = @novel.bible_locations.build
    @entry.name = params[:prefill_name] if params[:prefill_name].present?
  end

  def create
    @entry = @novel.bible_locations.build(entry_params)
    prefill_first_appearance_chapter(@entry)
    respond_to do |format|
      if @entry.save
        format.html { redirect_to edit_novel_bible_location_path(@novel, @entry), notice: "Location added. Fill in the details below." }
        format.json { render json: { id: @entry.id, display_name: @entry.name, edit_url: edit_novel_bible_location_path(@novel, @entry) }, status: :created }
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
        format.html { redirect_to novel_bible_location_path(@novel, @entry), notice: "Location updated." }
        format.json { render json: { id: @entry.id, display_name: @entry.name }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @entry.destroy
    redirect_to novel_bible_locations_path(@novel), notice: "Location removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_entry
    @entry = @novel.bible_locations.find(params[:id])
  end

  def entry_params
    params.require(:bible_location).permit(
      :name, :korean_name, :location_type, :description,
      :significance, :first_appearance_chapter, :notes
    )
  end
end
