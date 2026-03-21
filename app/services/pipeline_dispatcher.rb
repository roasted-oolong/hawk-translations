require "open3"

# ---------------------------------------------------------------------------
# PipelineDispatcher
#
# Responsible for one thing: translating a TranslationJob record into a
# shell command and executing it safely via Open3.capture3.
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
  PYTHON = "python3"

  def self.call(translation_job)
    new(translation_job).call
  end

  def initialize(translation_job)
    @job = translation_job
  end

  def call
    case @job.job_type
    when "preread"                 then run_preread
    when "bible_build"             then run_bible_build
    when "post_translation_review" then run_post_translation_review
    else
      [ "", "Unknown job_type: #{@job.job_type}", false ]
    end
  end

  private

  # ---------------------------------------------------------------------------
  # Preread — invokes run_preread.py with novel dir and chapter range.
  # ---------------------------------------------------------------------------
  def run_preread
    execute([ PYTHON, script("run_preread.py"),
              "--novel-dir",  novel_directory,
              "--chapters",   "#{@job.chapter_start}-#{@job.chapter_end}",
              "--batch-size", "5" ])
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

  # Executes a command array via Open3.capture3, returning [stdout, stderr, success?].
  # Passes the current process environment through so the Python pipeline picks
  # up ANTHROPIC_API_KEY and HAWK_PROJECT_ROOT from ENV.
  def execute(cmd)
    stdout, stderr, status = Open3.capture3(ENV.to_h, *cmd)
    [ stdout, stderr, status.success? ]
  rescue => e
    [ "", "Dispatch error: #{e.class}: #{e.message}", false ]
  end
end
