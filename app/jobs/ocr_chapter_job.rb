require "open3"

OCR_TIMEOUT_SECONDS = 600

class OcrChapterJob < ApplicationJob
  queue_as :default

  def perform(chapter_id, image_paths)
    chapter = Chapter.find_by(id: chapter_id)
    return unless chapter

    ActiveRecord::Base.connection_pool.release_connection
    text = run_ocr(image_paths)
    unless text
      chapter.update!(status: "ocr_failed")
      return
    end

    chapter.korean_source.attach(
      io:           StringIO.new(text),
      filename:     "ch#{chapter.number.to_s.rjust(3, '0')}_korean.txt",
      content_type: "text/plain"
    )
    KoreanSourceDiskWriter.new(chapter.novel).write(chapter)
    chapter.update!(status: "untranslated")
    FormatKoreanChapterJob.perform_later(chapter.id)
  ensure
    cleanup_tempfiles(image_paths)
  end

  private

  def run_ocr(paths)
    case PipelineImplementation.for("ocr")
    when :ruby
      run_ocr_ruby(paths)
    else
      run_ocr_python(paths)
    end
  end

  def run_ocr_ruby(paths)
    result = Pipeline::Ruby::OcrChapter.call(paths)
    unless result.success?
      Rails.logger.error("[OcrChapterJob] OCR failed: #{result.error_message}")
      return nil
    end
    result.output
  end

  def run_ocr_python(paths)
    python = ENV.fetch("PYTHON", "python3")
    script = File.join(project_root, "ocr_chapter.py")

    Open3.popen3(python, script, *paths) do |stdin, stdout, stderr, wait_thread|
      stdin.binmode
      stdin.close

      deadline = Time.now + OCR_TIMEOUT_SECONDS
      until wait_thread.join(1)
        if Time.now > deadline
          Process.kill("TERM", wait_thread.pid)
          wait_thread.join(5)
          Process.kill("KILL", wait_thread.pid) rescue nil
          Rails.logger.error("[OcrChapterJob] OCR script timed out after #{OCR_TIMEOUT_SECONDS}s")
          return nil
        end
      end

      status = wait_thread.value
      unless status.success?
        if status.signaled?
          Rails.logger.error(
            "[OcrChapterJob] OCR script was killed by signal #{status.termsig} " \
            "(signal 9/SIGKILL usually means the system ran out of memory):\n#{stderr.read}"
          )
        else
          Rails.logger.error("[OcrChapterJob] OCR script failed:\n#{stderr.read}")
        end
        return nil
      end

      stdout.read.force_encoding("UTF-8")
    end
  end

  def cleanup_tempfiles(paths)
    return if paths.blank?

    FileUtils.rm_rf(File.dirname(paths.first))
  end

  def project_root
    ENV.fetch("HAWK_PROJECT_ROOT") do
      raise "HAWK_PROJECT_ROOT environment variable is not set."
    end
  end
end
