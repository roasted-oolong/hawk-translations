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

  # Deleting a chapter must not leave its translated output behind: a stale
  # "Chapter <N>.txt" at the same number is exactly what
  # Pipeline::Ruby::TranslateBatch#attach_translated_outputs treats as "this
  # chapter already has a finished translation," so a later re-translate of
  # that chapter number would silently reattach the deleted chapter's text.
  def delete(chapter)
    path = chapter_path(chapter)
    File.delete(path) if File.exist?(path)
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
