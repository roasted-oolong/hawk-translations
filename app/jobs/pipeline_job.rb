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
    translation_job.update!(status: "running", progress_pct: 0)

    stop_polling = false
    progress_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        progress_file = "/tmp/hawk_job_#{translation_job.id}.progress"
        until stop_polling
          if File.exist?(progress_file)
            pct = File.read(progress_file).strip.to_i.clamp(0, 100)
            TranslationJob.where(id: translation_job.id).update_all(progress_pct: pct)
          end
          sleep 2
        end
        File.delete(progress_file) if File.exist?(progress_file)
      end
    end

    stdout, stderr, success = PipelineDispatcher.call(translation_job)

    stop_polling = true
    progress_thread.join

    if success
      translation_job.update!(
        status:         "completed",
        progress_pct:   100,
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
    stop_polling = true
    progress_thread&.join
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
