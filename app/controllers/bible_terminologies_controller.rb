class BibleTerminologiesController < ApplicationController
  before_action :set_novel
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @entries = @novel.bible_terminologies.by_term
  end

  def show; end

  def new
    @entry = @novel.bible_terminologies.build
  end

  def create
    @entry = @novel.bible_terminologies.build(entry_params)
    if @entry.save
      redirect_to novel_bible_terminology_path(@novel, @entry), notice: "Term added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      redirect_to novel_bible_terminology_path(@novel, @entry), notice: "Term updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to novel_bible_terminologies_path(@novel), notice: "Term removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_entry
    @entry = @novel.bible_terminologies.find(params[:id])
  end

  def entry_params
    params.require(:bible_terminology).permit(
      :term, :korean_term, :definition, :usage_notes,
      :first_appearance_chapter, :notes
    )
  end
end
