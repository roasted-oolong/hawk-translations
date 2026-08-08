class ChapterReviewController < ApplicationController
  before_action :set_novel

  def tab
    @chapters_for_review = @novel.chapters.translated.by_number
    @reviewed_count       = @novel.chapters.reviewed.count
    @total_count          = @novel.chapters.count

    pending            = BibleMarkdownParser.new(@novel).pending_entries
    @pending_breakdown = pending.transform_values(&:size)
    @pending_count     = @pending_breakdown.values.sum

    # Drives the poll wrapper around the "Preread Bible Entries" card (see
    # the view) — while a preread job is running, that card keeps re-fetching
    # this action so @pending_count/@pending_breakdown pick up newly-written
    # suggestions without the user refreshing the whole Review tab.
    @active_preread_job = @novel.translation_jobs.preread.where(status: %w[queued running]).exists?
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
    @korean_texts = @chapters.each_with_object({}) do |ch, h|
      h[ch.id] = ch.korean_source.attached? ? ch.korean_source.download.force_encoding("UTF-8") : nil
    end
    render layout: "review"
  end

  def update_text
    chapter = @novel.chapters.find(params[:id])
    text = params.require(:text)

    # Disk write goes first: if it fails, the request fails before the DB
    # attachment is touched, so a save either lands in both places or
    # neither — never disk-stale-but-DB-current.
    ChapterDiskWriter.new(@novel).write(chapter, text)

    chapter.translated_output.attach(
      io: StringIO.new(text),
      filename: "chapter_#{chapter.number}.txt",
      content_type: "text/plain"
    )
    head :ok
  end

  # GET .../chapter_review/chapters/:id/qa
  #
  # Polled by the review page after "Run Quality Check" is clicked. Returns
  # the latest chapter_qa job *for this chapter specifically* — not "the
  # latest chapter_qa job for the novel" like the voice_calibration/
  # post_translation_review review controllers do, since chapter_qa runs
  # per chapter and the page needs each chapter's own most recent run, not
  # whichever chapter was QA'd most recently across the whole novel.
  def qa_status
    chapter = @novel.chapters.find(params[:id])
    job = @novel.translation_jobs.chapter_qa
               .where(chapter_start: chapter.number, chapter_end: chapter.number)
               .order(created_at: :desc).first

    unless job
      render json: { status: "none" }
      return
    end

    payload = job.completed? ? (JSON.parse(job.result_payload) rescue {}) : {}
    render json: {
      id: job.id,
      status: job.status,
      progress_pct: job.progress_pct,
      suggestions: payload["suggestions"] || []
    }
  end

  # PATCH .../chapter_review/chapters/:id/qa/suggestions/:suggestion_id
  #
  # Bookkeeping only — records a suggestion's accept/reject decision so
  # re-opening the page doesn't re-prompt it. Does NOT touch chapter text;
  # applying an accepted suggestion's text is the existing update_text
  # action's job, same as any other edit to the chapter's content.
  def update_qa_suggestion
    chapter = @novel.chapters.find(params[:id])
    job = @novel.translation_jobs.chapter_qa.completed
               .where(chapter_start: chapter.number, chapter_end: chapter.number)
               .order(created_at: :desc).first
    head :not_found and return unless job

    payload     = JSON.parse(job.result_payload) rescue {}
    suggestions = payload["suggestions"] || []
    suggestion  = suggestions.find { |s| s["id"] == params[:suggestion_id] }
    head :not_found and return unless suggestion

    status = params.require(:status)
    unless status.in?(%w[accepted rejected])
      render json: { error: "Invalid status" }, status: :unprocessable_entity
      return
    end

    suggestion["status"] = status
    payload["suggestions"] = suggestions
    job.update!(result_payload: payload.to_json)

    render json: { ok: true }
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
