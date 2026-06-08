class ChapterReviewController < ApplicationController
  before_action :set_novel

  def tab
    @chapters_for_review = @novel.chapters.translated.by_number
    @reviewed_count       = @novel.chapters.reviewed.count
    @total_count          = @novel.chapters.count

    pending            = BibleMarkdownParser.new(@novel).pending_entries
    @pending_breakdown = pending.transform_values(&:size)
    @pending_count     = @pending_breakdown.values.sum
  end

  def show
    @chapters = @novel.chapters.translated.by_number
    if @chapters.empty?
      redirect_to novel_path(@novel), notice: "No translated chapters to review."
      return
    end
    @chapter_texts = @chapters.each_with_object({}) do |ch, h|
      h[ch.id] = ch.translated_output.attached? ? ch.translated_output.download.force_encoding("UTF-8") : ""
    end
    render layout: "review"
  end

  def update_text
    chapter = @novel.chapters.find(params[:id])
    text = params.require(:text)
    chapter.translated_output.attach(
      io: StringIO.new(text),
      filename: "chapter_#{chapter.number}.txt",
      content_type: "text/plain"
    )
    head :ok
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
