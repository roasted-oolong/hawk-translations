class BibleCulturalPhrasesController < ApplicationController
  PREREAD_CATEGORY = :cultural_phrases

  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]
  include BiblePrereadDismissed

  def index
    @entries = @novel.bible_cultural_phrases.by_phrase
  end

  def show; end

  def new
    @entry = @novel.bible_cultural_phrases.build
    @entry.phrase = params[:prefill_name] if params[:prefill_name].present?
  end

  def create
    @entry = @novel.bible_cultural_phrases.build(entry_params)
    respond_to do |format|
      if @entry.save
        format.html { redirect_to edit_novel_bible_cultural_phrase_path(@novel, @entry), notice: "Phrase added. Fill in the details below." }
        format.json { render json: { id: @entry.id, display_name: @entry.phrase, edit_url: edit_novel_bible_cultural_phrase_path(@novel, @entry) }, status: :created }
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
        format.html { redirect_to novel_bible_cultural_phrase_path(@novel, @entry), notice: "Phrase updated." }
        format.json { render json: { id: @entry.id, display_name: @entry.phrase }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity }
      end
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
