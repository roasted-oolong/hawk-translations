class PrereadReviewController < ApplicationController
  before_action :set_novel

  def show
    @proposals = @novel.bible_entry_proposals.includes(:chapter).order(:entry_type, :korean_key)

    if @proposals.empty?
      redirect_to novel_path(@novel), notice: "No pending preread entries. Dismissed entries can be restored from each bible category page."
      return
    end

    render layout: "review"
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
