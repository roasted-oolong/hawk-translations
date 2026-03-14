class BibleCulturalPhrasesController < ApplicationController
  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @entries = @novel.bible_cultural_phrases.by_phrase
  end

  def show; end

  def new
    @entry = @novel.bible_cultural_phrases.build
  end

  def create
    @entry = @novel.bible_cultural_phrases.build(entry_params)
    if @entry.save
      redirect_to novel_bible_cultural_phrase_path(@novel, @entry), notice: "Phrase added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      redirect_to novel_bible_cultural_phrase_path(@novel, @entry), notice: "Phrase updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to novel_bible_cultural_phrases_path(@novel), notice: "Phrase removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_entry
    @entry = @novel.bible_cultural_phrases.find(params[:id])
  end

  def entry_params
    params.require(:bible_cultural_phrase).permit(
      :phrase, :korean_phrase, :literal_translation, :intended_meaning,
      :context, :established_translation, :first_appearance_chapter, :notes
    )
  end
end
