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
  # Chapter status side-effects (preread + translate_batch jobs only):
  #   preread start   → chapters in range: untranslated/preread_failed → prereading
  #   preread success → chapters in range: prereading → preread
  #   preread failure → chapters in range: prereading → preread_failed
  #   translate_batch success → chapters in range: preread → translated
  # ---------------------------------------------------------------------------
  def perform(translation_job_id)
    translation_job = TranslationJob.find(translation_job_id)

    update_chapters(translation_job, :start)

    translation_job.update!(status: "running")

    stdout, stderr, success = PipelineDispatcher.call(translation_job)

    if success
      translation_job.update!(
        status:         "completed",
        result_payload: stdout.presence || "(no output)"
      )
      update_chapters(translation_job, :success)
    else
      translation_job.update!(
        status:         "failed",
        result_payload: [ stdout, stderr ].reject(&:blank?).join("\n").presence || "(no output)"
      )
      update_chapters(translation_job, :failure)
    end
  rescue => e
    translation_job&.update!(
      status:         "failed",
      result_payload: "Unexpected error: #{e.class}: #{e.message}"
    )
    update_chapters(translation_job, :failure) if translation_job
    raise
  end

  private

  def update_chapters(job, phase)
    chapters = job.novel.chapters
      .where(number: job.chapter_start..job.chapter_end)

    case [ job.job_type, phase.to_s ]
    in [ "preread", "start" ]            then chapters.update_all(status: "prereading")
    in [ "preread", "success" ]          then chapters.update_all(status: "preread")
    in [ "preread", "failure" ]          then chapters.update_all(status: "preread_failed")
    in [ "translate_batch", "success" ]  then chapters.update_all(status: "translated")
    else # no chapter status change for other job types / phases
    end
  end
end
