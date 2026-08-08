class BibleCharactersController < ApplicationController
  PREREAD_CATEGORY = :characters

  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]
  include BiblePrereadDismissed
  include BibleEntryChapterPrefill

  def index
    @entries = @novel.bible_characters.by_name
  end

  def show; end

  def new
    @entry = @novel.bible_characters.build
    @entry.name = params[:prefill_name] if params[:prefill_name].present?
  end

  def create
    @entry = @novel.bible_characters.build(entry_params)
    prefill_first_appearance_chapter(@entry)
    respond_to do |format|
      if @entry.save
        format.html { redirect_to edit_novel_bible_character_path(@novel, @entry), notice: "Character added. Fill in the details below." }
        format.json { render json: { id: @entry.id, display_name: @entry.name, edit_url: edit_novel_bible_character_path(@novel, @entry) }, status: :created }
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
        format.html { redirect_to novel_bible_character_path(@novel, @entry), notice: "Character updated." }
        format.json { render json: { id: @entry.id, display_name: @entry.name }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @entry.destroy
    redirect_to novel_bible_characters_path(@novel), notice: "Character removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_entry
    @entry = @novel.bible_characters.find(params[:id])
  end

  def entry_params
    params.require(:bible_character).permit(
      :name, :korean_name, :aliases, :role, :significance,
      :physical_description, :speech_pattern,
      :honorifics_used_toward, :honorifics_they_use,
      :relationships, :first_appearance_chapter, :notes
    )
  end
end
