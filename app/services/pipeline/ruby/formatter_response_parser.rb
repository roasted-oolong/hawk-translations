# ---------------------------------------------------------------------------
# Pipeline::Ruby::FormatterResponseParser
#
# Ruby port of src/formatter/response_parser.py — splits a batched formatting
# response into per-chapter text. No knowledge of the API, file I/O, or
# prompt construction.
#
# Deliberately does NOT fail-closed the way
# Pipeline::Ruby::PrereadRunner::ResponseParser does on zero section markers:
# a response missing some (or all) chapters is a per-chapter warning here,
# never a hard parse failure, matching Python's own behavior exactly (that
# rule is specific to preread's five-fixed-section shape; a formatting batch
# naming an open set of chapter numbers is a different, softer case in both
# the Python original and this port).
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    module FormatterResponseParser
      PATTERN = /===\s*CHAPTER\s+(\d+)\s*===\s*(.*?)\s*===\s*END CHAPTER\s+\1\s*===/m

      Result = Struct.new(:chapters, :missing, keyword_init: true)

      def self.parse(raw, expected_chapters)
        chapters = {}
        raw.scan(PATTERN) do |num_str, content|
          chapters[num_str.to_i] = content.strip
        end

        missing = expected_chapters.reject { |num| chapters.key?(num) }
        Rails.logger.warn("[FormatterResponseParser] response missing formatted output for chapters: #{missing}") if missing.any?

        Result.new(chapters: chapters, missing: missing)
      end
    end
  end
end
