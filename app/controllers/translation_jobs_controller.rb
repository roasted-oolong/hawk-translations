class TranslationJobsController < ApplicationController
  before_action :set_novel
  before_action :set_translation_job, only: [ :show, :destroy ]

  # ---------------------------------------------------------------------------
  # GET /novels/:novel_id/translation_jobs
  # Story #25 — job list with status
  # ---------------------------------------------------------------------------
  def index
    @translation_jobs   = @novel.translation_jobs.recent
    @translation_job    = TranslationJob.new
    @has_active_jobs    = @translation_jobs.any?(&:cancellable?)
  end

  # ---------------------------------------------------------------------------
  # GET /novels/:novel_id/translation_jobs/:id
  # Story #26 — output / error for a single job
  # ---------------------------------------------------------------------------
  def show
  end

  # ---------------------------------------------------------------------------
  # POST /novels/:novel_id/translation_jobs
  # Stories #22, #23, #24 — trigger a pipeline job
  # ---------------------------------------------------------------------------
  def create
    @translation_job = @novel.translation_jobs.new(translation_job_params)
    @translation_job.user = current_user

    if @translation_job.save
      enqueued = PipelineJob.perform_later(@translation_job.id)
      # Link to the Solid Queue row so StaleTranslationJobSweeper can verify
      # liveness; with the test adapter provider_job_id is nil, which is fine.
      @translation_job.update_column(:solid_queue_job_id, enqueued.provider_job_id)
      redirect_to novel_chapters_path(@novel),
                  notice: "#{@translation_job.job_type.humanize} job queued."
    else
      @translation_jobs = @novel.translation_jobs.recent
      render :index, status: :unprocessable_entity
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /novels/:novel_id/translation_jobs/:id
  # Story #27 — cancel a queued job
  # ---------------------------------------------------------------------------
  def destroy
    @translation_job.cancel!
    redirect_back fallback_location: novel_translation_job_path(@novel, @translation_job),
                  notice: "Job cancelled."
  end

  # ---------------------------------------------------------------------------
  # DELETE /novels/:novel_id/translation_jobs/bulk_cancel
  # Cancel multiple jobs in one request (e.g. selection-based cancel from the
  # chapters table or the "Cancel All" shortcut).
  # ---------------------------------------------------------------------------
  def bulk_cancel
    job_ids = Array(params[:job_ids]).map(&:to_i).uniq
    jobs    = @novel.translation_jobs.cancellable.where(id: job_ids)
    count   = 0
    jobs.each { |job| job.cancel! && count += 1 }
    redirect_to novel_chapters_path(@novel),
                notice: count.positive? ? "#{count} job(s) cancelled." : "No cancellable jobs found."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_translation_job
    # find_by! with explicit novel_id scope so a job belonging to a different
    # novel raises RecordNotFound rather than being silently accessible.
    @translation_job = TranslationJob.find_by!(
      id:       params[:id],
      novel_id: @novel.id
    )
  end

  def translation_job_params
    params.require(:translation_job).permit(
      :job_type,
      :chapter_start,
      :chapter_end
    ).then { |p| coerce_chapter_range(p) }
  end

  # Empty string chapter values (submitted when the form fields are blank,
  # e.g. for bible_build) must be coerced to nil so the model validation
  # treats them as absent rather than invalid integers.
  def coerce_chapter_range(permitted)
    permitted[:chapter_start] = nil if permitted[:chapter_start].blank?
    permitted[:chapter_end]   = nil if permitted[:chapter_end].blank?
    # Voice calibration and chapter QA both target a single chapter — end
    # defaults to start.
    if %w[voice_calibration chapter_qa].include?(permitted[:job_type]) && permitted[:chapter_end].nil?
      permitted[:chapter_end] = permitted[:chapter_start]
    end
    permitted
  end
end
