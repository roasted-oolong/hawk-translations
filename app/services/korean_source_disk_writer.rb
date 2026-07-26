# Keeps chapters/Chapter <N> (Korean).txt on disk in sync with the
# korean_source Active Storage attachment. src/novel_resolver.py discovers
# which chapters have Korean source (and are still untranslated) by scanning
# this directory for "*(Korean)*" filenames — never the database — so a
# chapter whose Korean text lives only in Active Storage is invisible to
# preread/translate no matter how far along it is in the app.
class KoreanSourceDiskWriter
  def initialize(novel)
    @novel = novel
  end

  # Writes atomically (temp file + rename) so a crash or concurrent read
  # mid-write can never leave a truncated file on disk. Raises on any
  # failure — including a missing HAWK_PROJECT_ROOT — rather than silently
  # leaving the pipeline unable to find a chapter it should be able to see.
  def write(chapter)
    return unless chapter.korean_source.attached?

    output_path = chapter_path(chapter)
    FileUtils.mkdir_p(File.dirname(output_path))

    tmp_path = "#{output_path}.#{SecureRandom.hex(8)}.tmp"
    File.binwrite(tmp_path, chapter.korean_source.download)
    File.rename(tmp_path, output_path)
  rescue => e
    File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
    raise e
  end

  # Deleting a chapter must not leave its source file behind: a stale
  # "*(Korean)*" file at the same chapter number would still be discoverable
  # by src/novel_resolver.py and Pipeline::Ruby's own chapter-discovery (see
  # PrereadRunner::ChapterDiscovery), so a later re-upload of that chapter
  # number would silently be re-fed the deleted chapter's old text.
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
    File.join(root, @novel.directory_name, "chapters", "Chapter #{chapter.number} (Korean).txt")
  end
end
