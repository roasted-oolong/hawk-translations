# ---------------------------------------------------------------------------
# Pipeline::Ruby::PrereadRunner::ResponseParser
#
# Ruby port of src/preread/response_parser.py — splits the model's structured
# preread response into the five canonical sections. No knowledge of the
# API, file I/O, or prompt construction.
#
# One deliberate hardening beyond the Python original (per
# docs/RAILS_REFACTOR_PLAN.md's R6 acceptance criteria, same fail-closed
# discipline R5 established): Python silently treats a response with none of
# the five headers the same as "every section legitimately empty" — its own
# "missing sections" warning is dead code, since results is pre-populated
# with every key before the check runs. This port distinguishes the two: a
# response with zero section markers at all is a hard parse failure the
# caller must check for (result.success?), never silently equivalent to a
# well-formed "nothing to add" response.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class PrereadRunner
      module ResponseParser
        SECTION_HEADERS = {
          characters:        "=== CHARACTERS ===",
          locations:         "=== LOCATIONS ===",
          terminology:       "=== TERMINOLOGY ===",
          cultural_phrases:  "=== CULTURAL PHRASES ===",
          story:             "=== STORY ==="
        }.freeze

        HEADER_PATTERN = /(#{SECTION_HEADERS.values.map { |h| Regexp.escape(h) }.join('|')})/

        Result = Struct.new(:sections, :missing_markers, keyword_init: true) do
          def success?
            !missing_markers
          end
        end

        def self.parse(raw)
          return Result.new(sections: {}, missing_markers: true) if SECTION_HEADERS.values.none? { |h| raw.include?(h) }

          sections = SECTION_HEADERS.keys.index_with { "" }
          parts = raw.split(HEADER_PATTERN)

          i = 1
          while i < parts.length - 1
            header_text  = parts[i].strip
            content_text = parts[i + 1] ? parts[i + 1].strip : ""
            i += 2

            key = SECTION_HEADERS.key(header_text)
            next unless key

            content_text = "" if content_text.strip.upcase == "NOTHING TO ADD"
            sections[key] = content_text
          end

          Result.new(sections: sections, missing_markers: false)
        end
      end
    end
  end
end
