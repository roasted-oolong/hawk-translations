# ---------------------------------------------------------------------------
# Pipeline::BibleUtils
#
# Ruby port of src/bible_utils.py — the single source of truth for
# deriving a canonical dedup key from a bible-entry "## heading" line.
# The Korean name/term is the canonical unique identifier for every bible
# entry; this module is what every reader/writer of bible files (R6's
# PrereadBibleWriter now, R5's BibleReviewWriter later) keys dedup on.
# ---------------------------------------------------------------------------
module Pipeline
  module BibleUtils
    KOREAN_PARENTHETICAL = /\(([^)]*[가-힣ᄀ-ᇿ㄰-㆏][^)]*)\)/
    HEADING_LINE = /^##\s+(.+)$/

    # Derive a canonical dedup key from a raw "## heading" string (everything
    # after the leading "## "). Priority: a parenthetical containing Korean
    # characters wins (lowercased, stripped) — this makes the Korean name the
    # single source of truth regardless of English romanisation. Otherwise,
    # normalise the English text: drop everything after " — " / " - " / " – ",
    # strip any remaining parentheticals, lowercase and strip.
    def self.heading_key(raw_heading)
      korean_match = KOREAN_PARENTHETICAL.match(raw_heading)
      return korean_match[1].strip.downcase if korean_match

      text = raw_heading.split(/\s+[—–-]\s+/, 2).first || raw_heading
      text = text.gsub(/\(.*?\)/, "")
      text.strip.downcase
    end

    # Return the set of canonical dedup keys for all ## headings in a
    # markdown string (a full bible file, or a single entry block).
    def self.extract_heading_keys(text)
      Set.new(text.scan(HEADING_LINE).map { |match| heading_key(match.first) })
    end
  end
end
