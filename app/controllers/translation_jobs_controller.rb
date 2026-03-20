class TranslationJobsController < ApplicationController
  before_action :set_novel
  before_action :set_translation_job, only: [ :show, :destroy ]

  # ---------------------------------------------------------------------------
  # GET /novels/:novel_id/translation_jobs
  # Story #25 — job list with status
  # ---------------------------------------------------------------------------
  def index
    @translation_jobs = @novel.translation_jobs.recent
    @translation_job  = TranslationJob.new
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
      PipelineJob.perform_later(@translation_job.id)
      redirect_to novel_translation_jobs_path(@novel),
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
    unless @translation_job.cancellable?
      redirect_to novel_translation_job_path(@novel, @translation_job),
                  alert: "This job cannot be cancelled — it is already #{@translation_job.status}."
      return
    end

    @translation_job.destroy!
    redirect_to novel_translation_jobs_path(@novel),
                notice: "Job cancelled."
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
    permitted
  end
end
