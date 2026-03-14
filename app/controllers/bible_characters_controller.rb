class BibleCharactersController < ApplicationController
  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @entries = @novel.bible_characters.by_name
  end

  def show; end

  def new
    @entry = @novel.bible_characters.build
  end

  def create
    @entry = @novel.bible_characters.build(entry_params)
    if @entry.save
      redirect_to novel_bible_character_path(@novel, @entry), notice: "Character added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      redirect_to novel_bible_character_path(@novel, @entry), notice: "Character updated."
    else
      render :edit, status: :unprocessable_entity
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
