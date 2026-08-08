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
      return normalize_korean(korean_match[1]) if korean_match

      text = raw_heading.split(/\s+[—–-]\s+/, 2).first || raw_heading
      text = text.gsub(/\(.*?\)/, "")
      normalize_korean(text)
    end

    # Normalise a Korean (or mixed Korean/Latin) string for stable identity
    # comparison — a dedup key, a preread_dismissed_keys entry, a bible-entry
    # lookup key. The LLM's exact rendering of the same underlying term can
    # drift run to run (stray whitespace, full-width vs half-width chars,
    # Latin-script casing) even though the term itself hasn't changed; every
    # caller that treats Korean text as an identity — not just as display
    # text — should normalise through this one method so "the same term"
    # reliably produces "the same key". Unicode-normalise (NFKC), collapse
    # internal whitespace, strip, and downcase (a no-op on Hangul, but keeps
    # any Latin-script terms case-insensitive too).
    def self.normalize_korean(str)
      str.to_s.unicode_normalize(:nfkc).gsub(/\s+/, " ").strip.downcase
    end

    # Return the set of canonical dedup keys for all ## headings in a
    # markdown string (a full bible file, or a single entry block).
    def self.extract_heading_keys(text)
      Set.new(text.scan(HEADING_LINE).map { |match| heading_key(match.first) })
    end
  end
end
