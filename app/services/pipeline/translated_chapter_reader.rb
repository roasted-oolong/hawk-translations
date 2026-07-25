# ---------------------------------------------------------------------------
# Pipeline::TranslatedChapterReader
#
# Shared chapter-file-selection rule for reading one already-translated
# chapter by number — ported once from the identical logic Python repeats in
# src/bible_review/bible_reader.py#read_translated_chapter and
# src/voice_calibration/chapter_reader.py#read_translated_chapter. Used by
# both Pipeline::Ruby::PostTranslationReview and Pipeline::Ruby::VoiceCalibration
# (see docs/RAILS_REFACTOR_PLAN.md's R5 section — "ported once, not three
# times if a shared helper is worth extracting here").
#
# A .txt file whose name contains "korean" or "another translation" is never
# a candidate — those are source/reference files, not the actual translation
# output.
# ---------------------------------------------------------------------------
module Pipeline
  module TranslatedChapterReader
    def self.find_file(chapters_dir, chapter_num)
      Dir.children(chapters_dir).find do |name|
        path = File.join(chapters_dir, name)
        next false unless File.file?(path)
        next false unless File.extname(name).downcase == ".txt"
        next false if name.downcase.include?("korean")
        next false if name.downcase.include?("another translation")

        extract_chapter_number(name) == chapter_num
      end&.then { |name| File.join(chapters_dir, name) }
    end

    # Returns the file's contents, or nil if no matching translated chapter
    # file exists — callers decide how to surface that (Python raises
    # FileNotFoundError; Ruby callers here return an error result instead).
    def self.read(chapters_dir, chapter_num)
      path = find_file(chapters_dir, chapter_num)
      path && File.read(path, encoding: "UTF-8")
    end

    def self.extract_chapter_number(filename)
      match = filename.match(/(\d+)/)
      match && match[1].to_i
    end
  end
end
