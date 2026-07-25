# ---------------------------------------------------------------------------
# Pipeline::Ruby::VoiceCalibration::ResponseParser
#
# Ruby port of calibrate-voice.py's own parsing helpers (_split_patterns,
# _split_retirements, _parse_pattern_entry — the response_parser.py section
# split, plus the card-building logic calibrate-voice.py does itself, since
# neither script separates them into their own module the way bible_review
# does). No knowledge of the API, file I/O, or prompt construction.
#
# Every field name below is load-bearing, verified directly against the
# real, already-shipped consumers per docs/RAILS_REFACTOR_PLAN.md's R5
# acceptance criteria: VoiceCalibrationReviewController#apply_card! reads
# card["heading"]/["chapter_ref"]/["quote"]/["what_it_demonstrates"]/
# ["wrong_version"]/["rule"] for "new_pattern" cards, and
# PipelineJob#build_result_payload enriches "retirement" cards with
# passage_id/quote afterward — neither is touched by this design, so the
# wire-format hash produced here must match exactly. Unlike
# PostTranslationReview's cards, these carry no "decision" key at generation
# time (calibrate-voice.py's own output never had one; the review
# controller adds it later) — a deliberate difference, not an oversight.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class VoiceCalibration
      module ResponseParser
        SECTION_HEADERS = {
          new_patterns: "=== NEW PATTERNS ===",
          retirements:  "=== RETIREMENTS ==="
        }.freeze

        HEADER_PATTERN = /(#{SECTION_HEADERS.values.map { |h| Regexp.escape(h) }.join('|')})/

        NewPatternCard = Data.define(:id, :heading, :chapter_ref, :quote, :what_it_demonstrates,
                                      :wrong_version, :rule) do
          def to_card_hash
            {
              "id" => id, "card_type" => "new_pattern", "heading" => heading,
              "chapter_ref" => chapter_ref, "quote" => quote,
              "what_it_demonstrates" => what_it_demonstrates,
              "wrong_version" => wrong_version, "rule" => rule
            }
          end
        end

        RetirementCard = Data.define(:id, :heading, :reason) do
          def to_card_hash
            { "id" => id, "card_type" => "retirement", "heading" => heading, "reason" => reason }
          end
        end

        Result = Struct.new(:cards, :failure_reason, :error_message, keyword_init: true) do
          def success?
            failure_reason.nil?
          end
        end

        def self.parse(raw)
          unless SECTION_HEADERS.values.any? { |header| raw.include?(header) }
            return Result.new(cards: [], failure_reason: :missing_markers,
                               error_message: "response contains neither required section marker")
          end

          sections = split_top_sections(raw)
          cards = parse_new_patterns(sections[:new_patterns]) + parse_retirements(sections[:retirements])
          Result.new(cards: cards)
        end

        def self.split_top_sections(raw)
          sections = SECTION_HEADERS.keys.index_with { "" }
          parts = raw.split(HEADER_PATTERN)

          i = 1
          while i < parts.length - 1
            header_text  = parts[i].strip
            content_text = parts[i + 1] ? parts[i + 1].strip : ""
            i += 2

            key = SECTION_HEADERS.key(header_text)
            next unless key

            sections[key] = content_text.upcase == "NOTHING TO REPORT" ? "" : content_text
          end
          sections
        end
        private_class_method :split_top_sections

        def self.parse_new_patterns(raw)
          return [] if raw.strip.empty?

          patterns = raw.split(/(?=^## )/).map(&:strip).reject(&:empty?)
          patterns.each_with_index.map { |text, i| build_pattern_card(text, i) }
        end
        private_class_method :parse_new_patterns

        def self.build_pattern_card(text, index)
          heading_match = text.match(/\A##\s+(.+)/)
          chapter_match = text.match(/^\*(.+?)\*\s*$/)
          quote = text.lines.select { |line| line.start_with?("> ") }
                       .map { |line| line.delete_prefix("> ").chomp }
                       .join("\n").strip
          demonstrates_match = text.match(/\*\*What it demonstrates:\*\*\s*(.+?)(?=\*\*What the wrong|\z)/m)
          wrong_match        = text.match(/\*\*What the wrong version looks like:\*\*\s*(.+?)(?=\*\*The rule|\z)/m)
          rule_match         = text.match(/\*\*The rule it demonstrates:\*\*\s*(.+?)(?=---|\z)/m)

          NewPatternCard.new(
            id:                   "new_pattern_#{index}",
            heading:              heading_match ? heading_match[1].strip : "",
            chapter_ref:          chapter_match ? chapter_match[1].strip : "",
            quote:                quote,
            what_it_demonstrates: demonstrates_match ? demonstrates_match[1].strip : "",
            wrong_version:        wrong_match ? wrong_match[1].strip : "",
            rule:                 rule_match ? rule_match[1].strip : ""
          )
        end
        private_class_method :build_pattern_card

        def self.parse_retirements(raw)
          return [] if raw.strip.empty?

          blocks = raw.split(/(?=\*\*Retirement candidate)/)
          items = blocks.filter_map do |block|
            block = block.strip
            next if block.empty?

            heading_match = block.match(/\*\*Retirement candidate[^*]*?[—-]\s*(.+?)\*\*/)
            reason_match  = block.match(/Reason:\s*(.+)/)
            next unless heading_match && reason_match

            [ heading_match[1].strip, reason_match[1].strip ]
          end

          items.each_with_index.map do |(heading, reason), i|
            RetirementCard.new(id: "retirement_#{i}", heading: heading, reason: reason)
          end
        end
        private_class_method :parse_retirements
      end
    end
  end
end
