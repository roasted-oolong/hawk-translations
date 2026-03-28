# app/services/chapter_file_classifier.rb
#
# Single-responsibility service that classifies an uploaded chapter file.
#
# Given an IO-like stream and a filename, #classify returns:
#   {
#     language:       :korean | :english,
#     chapter_number: Integer | nil
#   }
#
# Language is determined entirely from file content — the filename is never
# consulted for language. Chapter number is determined entirely from the
# filename — file content is never consulted for number.
#
# Language detection algorithm:
#   Read the first SAMPLE_BYTES bytes. Count all non-whitespace characters.
#   If more than 50% of those characters fall in the Hangul syllable block
#   (U+AC00–U+D7A3), classify as :korean; otherwise :english.
#   A file with no non-whitespace characters is :english.
#   Using all non-whitespace (not just non-ASCII) as the denominator ensures
#   that a handful of Hangul footnote characters in an otherwise ASCII file
#   do not cause a false :korean classification.
#
# Chapter number extraction patterns (tried in order; first match wins):
#   1. /(\d+)화/  — e.g. "3화.txt", "제3화.txt", "소설_10화_원고.txt"
#   2. /\AChapter\s+(\d+)/i — e.g. "Chapter 3.txt", "chapter 3 - Title.txt"
#   If neither matches, chapter_number is nil.

class ChapterFileClassifier
  SAMPLE_BYTES = 4096

  HANGUL_FIRST = 0xAC00
  HANGUL_LAST  = 0xD7A3

  HWA_PATTERN     = /(\d+)화/
  CHAPTER_PATTERN = /\AChapter\s+(\d+)/i

  def initialize(stream, filename)
    @stream   = stream
    @filename = filename
  end

  def classify
    {
      language:       detect_language,
      chapter_number: extract_chapter_number
    }
  end

  private

  def detect_language
    sample   = read_sample
    chars    = sample.chars

    non_whitespace = chars.reject { |c| c.strip == "" }
    return :english if non_whitespace.empty?

    hangul_count = non_whitespace.count { |c| hangul?(c) }
    hangul_count.to_f / non_whitespace.size > 0.5 ? :korean : :english
  end

  def extract_chapter_number
    base = File.basename(@filename, ".*")

    if (m = base.match(HWA_PATTERN))
      return m[1].to_i
    end

    if (m = base.match(CHAPTER_PATTERN))
      return m[1].to_i
    end

    nil
  end

  def read_sample
    @stream.rewind if @stream.respond_to?(:rewind)
    raw = @stream.read(SAMPLE_BYTES) || ""
    # Force encoding to UTF-8, replacing any invalid byte sequences so that
    # #chars doesn't raise on malformed input.
    raw.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  def hangul?(char)
    ord = char.ord
    ord >= HANGUL_FIRST && ord <= HANGUL_LAST
  end
end
