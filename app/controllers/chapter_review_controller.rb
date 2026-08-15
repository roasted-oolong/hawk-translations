class ChapterReviewController < ApplicationController
  before_action :set_novel

  def tab
    @chapters_for_review = @novel.chapters.translated.by_number
    @reviewed_count       = @novel.chapters.reviewed.count
    @total_count          = @novel.chapters.count

    # The "Preread Bible Entries" card also gets pushed fresh values over
    # Turbo Streams as preread jobs progress — see
    # TranslationJob#broadcast_preread_entries_status — so this is just the
    # initial render.
    breakdown           = @novel.pending_preread_breakdown
    @pending_count     = breakdown[:total]
    @pending_breakdown = breakdown[:by_category]
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

    # Reopen the slideshow on whichever chapter the reviewer was last on,
    # not always chapter 1 — the whole point of resume tracking. Falls back
    # to 0 if there's no saved chapter, or it's since left @chapters (e.g.
    # already marked reviewed, so filtered out by the .translated scope
    # above) rather than raising or silently pinning to the last chapter.
    @resume_index = @chapters.index { |c| c.id == @novel.last_reviewed_chapter_id } || 0

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

  # PATCH .../chapter_review/chapters/:id/position
  #
  # Fired on a debounce while the reviewer scrolls, plus immediately before
  # any chapter switch and on page unload — see chapter_review_controller.ts.
  # update_column/update_columns rather than update!: this fires often and
  # carries no meaningful validation or callback surface (last_scroll_position
  # is clamped client-side already; nothing else on Chapter/Novel needs to
  # react to a scroll position changing), so a plain write keeps a frequent,
  # low-stakes ping cheap instead of running full save machinery for it.
  def update_position
    chapter = @novel.chapters.find(params[:id])
    position = params.require(:scroll_position).to_f.clamp(0.0, 1.0)

    chapter.update_column(:last_scroll_position, position)
    @novel.update_column(:last_reviewed_chapter_id, chapter.id)

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
