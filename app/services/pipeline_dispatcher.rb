# ---------------------------------------------------------------------------
# PipelineDispatcher
#
# Responsible for one thing: translating a TranslationJob record into a
# shell command and executing it safely via Pipeline::Subprocess.run.
#
# Returns [stdout, stderr, success?] — the job class decides what to do
# with the result. This class knows nothing about job status lifecycle.
#
# Design notes:
# - Commands are built from config values and validated TranslationJob fields,
#   never from raw user input. Paths are passed as discrete array elements to
#   Open3 rather than interpolated into a shell string, avoiding any escaping
#   concerns.
# - novel.directory_name is the exact filesystem directory name (e.g.
#   "idols-rewind"), distinct from novel.title which is UI display text.
# - HAWK_PROJECT_ROOT is read from ENV at dispatch time, not at boot, so the
#   value is always current.
# - bible_build runs preread on already-translated chapters to rebuild bible
#   entries. It accepts the same chapter range format as preread.
# ---------------------------------------------------------------------------
class PipelineDispatcher
  PYTHON = ENV.fetch("PYTHON", "python3")

  # Matches PipelineJob's own 4-hour concurrency-limiter window for local-LLM
  # endpoints — a single job is already expected to legitimately take close
  # to that long on local hardware. This preserves today's de facto
  # unbounded runtime for realistic workloads while still bounding a
  # genuinely hung process instead of letting it run forever.
  EXECUTE_TIMEOUT = 4.hours

  def self.call(translation_job)
    new(translation_job).call
  end

  def initialize(translation_job)
    @job = translation_job
  end

  def call
    # chapter_qa has no Python implementation and never will (it's a
    # production-native Ruby feature, not a migrated-from-Python one) — it
    # deliberately bypasses PipelineImplementation rather than adding a
    # PIPELINE_IMPL_CHAPTER_QA entry, since that lookup defaults to
    # "python" when unset, which would silently misroute this job type to
    # dispatch_python's "Unknown job_type" failure in any environment that
    # forgot to set the override.
    return Pipeline::Ruby::ChapterQa.call(@job) if @job.job_type == "chapter_qa"

    case PipelineImplementation.for(@job.job_type)
    when :python then dispatch_python
    when :ruby   then dispatch_ruby
    end
  end

  private

  # Two flat per-job-type dispatch tables, not one interleaved structure —
  # configuration lookup (above) and routing (here) are different
  # responsibilities and stay legible as separate ones.
  def dispatch_python
    case @job.job_type
    when "preread"                 then run_preread
    when "translate_batch"         then run_translate_batch
    when "bible_build"             then run_bible_build
    when "post_translation_review" then run_post_translation_review
    when "voice_calibration"       then run_voice_calibration
    else
      [ "", "Unknown job_type: #{@job.job_type}", false ]
    end
  end

  # Ruby implementations are stubs today (each raises NotImplementedError
  # internally) — this dispatch structure is not expected to change again as
  # R1-R6 land; only the stubs' internals do.
  def dispatch_ruby
    case @job.job_type
    when "preread"                 then Pipeline::Ruby::Preread.call(@job)
    when "translate_batch"         then Pipeline::Ruby::TranslateBatch.call(@job)
    when "bible_build"             then Pipeline::Ruby::BibleBuild.call(@job)
    when "post_translation_review" then Pipeline::Ruby::PostTranslationReview.call(@job)
    when "voice_calibration"       then Pipeline::Ruby::VoiceCalibration.call(@job)
    else
      [ "", "Unknown job_type: #{@job.job_type}", false ]
    end
  end

  # ---------------------------------------------------------------------------
  # Preread — invokes run_preread.py with novel dir and chapter range.
  # ---------------------------------------------------------------------------
  def run_preread
    execute([ PYTHON, script("run_preread.py"),
              "--novel-dir",  novel_directory,
              "--chapters",   "#{@job.chapter_start}-#{@job.chapter_end}",
              "--batch-size", "2" ])
  end

  # ---------------------------------------------------------------------------
  # Translate batch — invokes translate_batch.py with chapter selection and novel name.
  # translate_batch.py takes positional args: <chapter_selection> [novel_name]
  # ---------------------------------------------------------------------------
  def run_translate_batch
    chapter_arg = @job.chapter_start == @job.chapter_end \
      ? @job.chapter_start.to_s \
      : "#{@job.chapter_start}-#{@job.chapter_end}"
    execute([ PYTHON, script("translate_batch.py"),
              chapter_arg,
              @job.novel.directory_name ])
  end

  # ---------------------------------------------------------------------------
  # Bible build — invokes run_bible_build.py with novel dir and chapter range.
  # Runs preread on already-translated chapters to rebuild bible entries.
  # ---------------------------------------------------------------------------
  def run_bible_build
    execute([ PYTHON, script("run_bible_build.py"),
              "--novel-dir", novel_directory,
              "--chapters",  "#{@job.chapter_start}-#{@job.chapter_end}" ])
  end

  # ---------------------------------------------------------------------------
  # Post-translation review — invokes run_review.py with novel dir and chapter.
  # chapter_start == chapter_end for single-chapter jobs (enforced by model).
  # ---------------------------------------------------------------------------
  def run_post_translation_review
    execute([ PYTHON, script("run_review.py"),
              "--novel-dir", novel_directory,
              "--chapter",   @job.chapter_start.to_s ])
  end

  # ---------------------------------------------------------------------------
  # Voice calibration — invokes calibrate-voice.py with novel name and chapter.
  # ---------------------------------------------------------------------------
  def run_voice_calibration
    execute([ PYTHON, script("calibrate-voice.py"),
              @job.novel.directory_name,
              @job.chapter_start.to_s ])
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Absolute path to a script at the project root.
  def script(filename)
    File.join(project_root, filename)
  end

  # Absolute path to the novel's directory on disk.
  # Uses novel.directory_name — the explicit filesystem name set when the
  # novel was created, distinct from the UI display title.
  def novel_directory
    File.join(project_root, @job.novel.directory_name)
  end

  # Project root from ENV. Raises clearly if missing so misconfiguration is
  # immediately obvious rather than silently producing a wrong path.
  def project_root
    ENV.fetch("HAWK_PROJECT_ROOT") do
      raise "HAWK_PROJECT_ROOT environment variable is not set. " \
            "Check .env (development) or Rails credentials (production)."
    end
  end

  # Executes a command array via Pipeline::Subprocess.run, returning
  # [stdout, stderr, success?]. Passes the current process environment
  # through so the Python pipeline picks up ANTHROPIC_API_KEY and
  # HAWK_PROJECT_ROOT from ENV.
  def execute(cmd)
    env = ENV.to_h.merge("HAWK_JOB_ID" => @job.id.to_s)
    result = Pipeline::Subprocess.run(cmd, env: env, timeout: EXECUTE_TIMEOUT, name: @job.job_type)
    [ result.stdout, result.stderr, result.success? ]
  rescue => e
    [ "", "Dispatch error: #{e.class}: #{e.message}", false ]
  end
end
