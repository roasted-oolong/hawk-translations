require "open3"

CLEANER_TIMEOUT_SECONDS = 300

class FormatKoreanChapterJob < ApplicationJob
  queue_as :default

  def perform(chapter_id)
    chapter = Chapter.find_by(id: chapter_id)
    return unless chapter&.korean_source&.attached?

    original = chapter.korean_source.download

    ActiveRecord::Base.connection_pool.release_connection
    cleaned = run_cleaner(original)
    return unless cleaned

    chapter.korean_source.attach(
      io:           StringIO.new(cleaned),
      filename:     chapter.korean_source.filename.to_s,
      content_type: chapter.korean_source.content_type
    )
  end

  private

  def run_cleaner(text)
    python = ENV.fetch("PYTHON", "python3")
    script = File.join(project_root, "clean_chapter.py")

    Open3.popen3(python, script) do |stdin, stdout, stderr, wait_thread|
      stdin.binmode
      stdin.write(text)
      stdin.close

      deadline = Time.now + CLEANER_TIMEOUT_SECONDS
      until wait_thread.join(1)
        if Time.now > deadline
          Process.kill("TERM", wait_thread.pid)
          wait_thread.join(5)
          Process.kill("KILL", wait_thread.pid) rescue nil
          Rails.logger.error("[FormatKoreanChapterJob] cleaner script timed out after #{CLEANER_TIMEOUT_SECONDS}s")
          return nil
        end
      end

      unless wait_thread.value.success?
        Rails.logger.error("[FormatKoreanChapterJob] cleaner script failed:\n#{stderr.read}")
        return nil
      end

      stdout.read.force_encoding("UTF-8")
    end
  end

  def project_root
    ENV.fetch("HAWK_PROJECT_ROOT") do
      raise "HAWK_PROJECT_ROOT environment variable is not set."
    end
  end
end
