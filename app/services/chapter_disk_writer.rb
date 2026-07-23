# Keeps chapters/Chapter <N>.txt on disk in sync with edits made in the
# review UI. src/voice_calibration/chapter_reader.py reads chapter text from
# that flat file directly — never from the translated_output Active Storage
# attachment — so a reviewed chapter's revisions have to land on disk or
# voice calibration silently runs against the pre-review machine translation.
class ChapterDiskWriter
  def initialize(novel)
    @novel = novel
  end

  # Writes text atomically (temp file + rename) so a crash or concurrent
  # read mid-write can never leave a truncated chapter file on disk. Raises
  # on any failure — including a missing HAWK_PROJECT_ROOT — rather than
  # swallowing it, so the caller can refuse to save an edit that didn't
  # reach disk instead of leaving the DB and disk copies disagreeing.
  def write(chapter, text)
    output_path = chapter_path(chapter)
    FileUtils.mkdir_p(File.dirname(output_path))

    tmp_path = "#{output_path}.#{SecureRandom.hex(8)}.tmp"
    File.write(tmp_path, text, encoding: "UTF-8")
    File.rename(tmp_path, output_path)
  rescue => e
    File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
    raise e
  end

  private

  def chapter_path(chapter)
    root = ENV.fetch("HAWK_PROJECT_ROOT") do
      raise "HAWK_PROJECT_ROOT environment variable is not set. " \
            "Check .env (development) or Rails credentials (production)."
    end
    File.join(root, @novel.directory_name, "chapters", "Chapter #{chapter.number}.txt")
  end
end
