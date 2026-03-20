class PipelineJob < ApplicationJob
  queue_as :default

  # ---------------------------------------------------------------------------
  # Perform
  #
  # Drives a TranslationJob record through its lifecycle:
  #   queued → running → completed | failed
  #
  # The actual work is delegated to a dispatcher that shells out to the
  # appropriate Python script via Open3.capture3.
  #
  # Parameters
  # ----------
  # translation_job_id : Integer
  #   ID of the TranslationJob record to execute. Looked up fresh inside the
  #   job so stale in-memory state from the caller is never used.
  # ---------------------------------------------------------------------------
  def perform(translation_job_id)
    translation_job = TranslationJob.find(translation_job_id)

    translation_job.update!(status: "running")

    stdout, stderr, success = PipelineDispatcher.call(translation_job)

    if success
      translation_job.update!(
        status:         "completed",
        result_payload: stdout.presence || "(no output)"
      )
    else
      translation_job.update!(
        status:         "failed",
        result_payload: [ stdout, stderr ].reject(&:blank?).join("\n").presence || "(no output)"
      )
    end
  rescue => e
    # Catch unexpected errors (e.g. TranslationJob record deleted mid-flight,
    # dispatcher raises, etc.) and record them so the job doesn't silently vanish.
    translation_job&.update!(
      status:         "failed",
      result_payload: "Unexpected error: #{e.class}: #{e.message}"
    )
    raise
  end
end
