# ---------------------------------------------------------------------------
# StaleTranslationJobSweeper
#
# Detects TranslationJob records stuck in queued/running because their
# Solid Queue worker died out-of-process (SIGKILL, OOM, host reboot). In
# that case PipelineJob's rescue never runs, so nothing transitions the
# record to failed — it shows as "running" in the UI forever.
#
# A job is considered dead when its linked SolidQueue::Job:
#   - no longer exists (only finished jobs are ever cleared), or
#   - has a failed execution (e.g. ProcessPrunedError after a worker death), or
#   - finished without the TranslationJob ever leaving queued/running.
#
# Jobs with no recorded solid_queue_job_id are skipped — liveness cannot
# be verified. Ready/scheduled/claimed executions are left alone: a queued
# job waiting for a worker to come online is not dead.
#
# Runs on a schedule via config/recurring.yml.
# ---------------------------------------------------------------------------
class StaleTranslationJobSweeper
  DEAD_WORKER_MESSAGE =
    "The background worker died while this job was in flight " \
    "(process killed or host restarted). Re-run the job to retry.".freeze

  def self.call
    new.call
  end

  def call
    TranslationJob.cancellable.where.not(solid_queue_job_id: nil).find_each do |job|
      job.mark_dead!(DEAD_WORKER_MESSAGE) if dead?(job)
    end
  end

  private

  def dead?(translation_job)
    sq_job = SolidQueue::Job.find_by(id: translation_job.solid_queue_job_id)

    sq_job.nil? ||
      sq_job.failed_execution.present? ||
      sq_job.finished_at.present?
  end
end
