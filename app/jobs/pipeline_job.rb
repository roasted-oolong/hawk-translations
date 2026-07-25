class PipelineJob < ApplicationJob
  queue_as :default

  # Mirrors src/agent.py _is_local_endpoint: loopback and private-network hosts
  # run on the user's own hardware, so jobs are serialised globally to avoid
  # GPU contention. Remote/paid endpoints keep the default concurrent behaviour.
  def self.local_llm_endpoint?
    require "uri"
    require "ipaddr"
    host = URI.parse(ENV.fetch("LLM_BASE_URL", "http://localhost:11434/v1")).host.to_s
    return true if %w[localhost ::1].include?(host)
    addr = IPAddr.new(host)
    addr.loopback? || addr.private?
  rescue IPAddr::InvalidAddressError
    false
  end
  private_class_method :local_llm_endpoint?

  limits_concurrency to: 1, key: "pipeline_job", duration: 4.hours if local_llm_endpoint?

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
  #   translate_batch (success or failure) → each chapter in range with a
  #     written output file on disk: preread → translated. Per-chapter, not
  #     all-or-nothing: a partial-failure translate_batch job (R4) still
  #     attaches and marks every chapter that succeeded before the failure.
  # ---------------------------------------------------------------------------
  def perform(translation_job_id)
    translation_job = TranslationJob.find(translation_job_id)
    return if translation_job.cancelled?

    update_chapters(translation_job, :start)
    translation_job.update!(status: "running", progress_pct: 0)

    stop_polling = false
    progress_thread = Thread.new do
      progress_file = "/tmp/hawk_job_#{translation_job.id}.progress"
      until stop_polling
        if File.exist?(progress_file)
          pct = File.read(progress_file).strip.to_i.clamp(0, 100)
          ActiveRecord::Base.connection_pool.with_connection do
            TranslationJob.where(id: translation_job.id).update_all(progress_pct: pct)
          end
        end
        sleep 2
      end
      File.delete(progress_file) if File.exist?(progress_file)
    end

    stdout, stderr, success = PipelineDispatcher.call(translation_job)

    stop_polling = true
    progress_thread.join

    translation_job.reload
    return if translation_job.cancelled?

    if success
      translation_job.update!(
        status:         "completed",
        progress_pct:   100,
        result_payload: build_result_payload(translation_job, stdout)
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

  # Per-chapter, not all-or-nothing: a translate_batch job that fails
  # partway through (R4's recoverable/fatal error-category split, see
  # docs/RAILS_REFACTOR_PLAN.md) still writes every chapter that succeeded
  # before the failure. Attaching and marking "translated" is keyed off
  # whether that chapter's own output file actually exists on disk, not off
  # the job's overall success/failure status — so those chapters aren't
  # silently left un-attached and stuck at their pre-job status just because
  # a later chapter in the same range failed. Called from both the
  # "success" and "failure" branches of update_chapters below.
  def attach_translated_outputs(job, chapters)
    novel_dir = File.join(
      ENV.fetch("HAWK_PROJECT_ROOT"),
      job.novel.directory_name
    )

    chapters.each do |chapter|
      output_path = File.join(novel_dir, "chapters", "Chapter #{chapter.number}.txt")
      next unless File.exist?(output_path)

      File.open(output_path) do |file|
        chapter.translated_output.attach(
          io:           file,
          filename:     "Chapter_#{chapter.number}.txt",
          content_type: "text/plain"
        )
      end
      chapter.update!(status: "translated")
    end
  end

  def build_result_payload(job, stdout)
    return stdout.presence || "(no output)" unless job.voice_calibration?

    data     = JSON.parse(stdout)
    cards    = data["cards"] || []
    passages = job.novel.voice_calibration_passages.to_a
    cards.each do |card|
      next unless card["card_type"] == "retirement"
      passage = passages.find { |p| normalize_heading(p.heading) == normalize_heading(card["heading"]) }
      card["passage_id"] = passage&.id
      card["quote"]      = passage&.quote
    end
    data.to_json
  rescue JSON::ParserError
    stdout.presence || "(no output)"
  end

  # The review model always cites a passage heading as it appears in
  # voice_calibration.md (which includes a "Passage N — " prefix), but some
  # passages were backfilled into the DB with just the descriptive title.
  # Matching on the description only keeps retirement lookups working
  # regardless of which format a given passage's heading is stored in.
  def normalize_heading(text)
    text.to_s.sub(/\APassage\s+\S+\s*[—-]\s*/, "").strip.downcase
  end

  def update_chapters(job, phase)
    chapters = job.novel.chapters
      .where(number: job.chapter_start..job.chapter_end)

    case [ job.job_type, phase.to_s ]
    in [ "preread", "start" ]            then chapters.update_all(status: "prereading")
    in [ "preread", "success" ]          then chapters.update_all(status: "preread")
    in [ "preread", "failure" ]          then chapters.update_all(status: "preread_failed")
    in [ "translate_batch", "success" ] | [ "translate_batch", "failure" ]
      attach_translated_outputs(job, chapters)
    else # no chapter status change for other job types / phases
    end
  end
end
