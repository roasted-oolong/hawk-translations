class BibleLocationsController < ApplicationController
  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @entries = @novel.bible_locations.by_name
  end

  def show; end

  def new
    @entry = @novel.bible_locations.build
  end

  def create
    @entry = @novel.bible_locations.build(entry_params)
    if @entry.save
      redirect_to novel_bible_location_path(@novel, @entry), notice: "Location added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      redirect_to novel_bible_location_path(@novel, @entry), notice: "Location updated."
    else
      render :edit, status: :unprocessable_entity
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
