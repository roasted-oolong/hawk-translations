# ---------------------------------------------------------------------------
# Pipeline::Ruby::PostTranslationReview::ResponseParser
#
# Ruby port of src/bible_review/response_parser.py, hardened per
# docs/RAILS_REFACTOR_PLAN.md's R5 acceptance criteria (round 1 review):
# fail-closed on a response missing its top-level section markers entirely
# (distinct from "present but empty," a legitimate "nothing to report"),
# stricter per-block validation (a malformed block is rejected and does not
# become a card, rather than being silently absorbed into an adjacent
# entry), and response-level size/count/field-length caps checked before any
# card is constructed. No knowledge of the API, file I/O, or prompt
# construction.
#
# New entries, proposed edits, and story updates are represented as typed
# Data.define value objects from parse time onward (NewBibleEntry /
# ProposedBibleEdit / StoryUpdate) rather than raw hashes — impossible-
# invalid-state by construction. Each knows how to serialize itself to the
# wire-format card hash (#to_card_hash) that Pipeline::Ruby::PostTranslationReview
# emits as JSON and PostTranslationReviewController/BibleReviewWriter consume.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class PostTranslationReview
      module ResponseParser
        MAX_RESPONSE_BYTES = 200 * 1024
        MAX_CARDS          = 50
        MAX_FIELD_LENGTH   = 5_000

        SECTION_HEADERS = {
          new_entries:    "=== NEW ENTRIES ===",
          proposed_edits: "=== PROPOSED EDITS ===",
          story_updates:  "=== STORY UPDATES ==="
        }.freeze

        HEADER_PATTERN     = /(#{SECTION_HEADERS.values.map { |h| Regexp.escape(h) }.join('|')})/
        FILE_LABEL_HEADER   = /^###\s*([a-zA-Z_\s]+?(?:\.md)?)\s*$/i
        KEYED_FIELD_PATTERN = ->(keys) { /^(#{keys.join('|')})\s*:\s*(.*)/i }

        # Normalises both the ### file-label headers under NEW ENTRIES and
        # the FILE: field of a proposed edit to one canonical section key —
        # a single table subsuming Python's two separate (but overlapping)
        # _FILE_LABEL_TO_KEY maps in response_parser.py and runner.py.
        FILE_LABEL_TO_KEY = {
          "characters"       => "characters",
          "character"        => "characters",
          "locations"        => "locations",
          "location"         => "locations",
          "terminology"      => "terminology",
          "term"             => "terminology",
          "cultural phrases" => "cultural_phrases",
          "cultural phrase"  => "cultural_phrases",
          "story"            => "story"
        }.freeze

        NewBibleEntry = Data.define(:id, :section_key, :heading, :content) do
          def to_card_hash
            {
              "id" => id, "card_type" => "new_entry", "decision" => "pending",
              "section_key" => section_key, "heading" => heading, "content" => content
            }
          end
        end

        ProposedBibleEdit = Data.define(:id, :entry, :section_key, :current, :proposed, :reason) do
          def to_card_hash
            {
              "id" => id, "card_type" => "proposed_edit", "decision" => "pending",
              "entry" => entry, "section_key" => section_key,
              "current" => current, "proposed" => proposed, "reason" => reason
            }
          end
        end

        StoryUpdate = Data.define(:id, :type, :update) do
          def to_card_hash
            {
              "id" => id, "card_type" => "story_update", "decision" => "pending",
              "type" => type, "update" => update
            }
          end
        end

        Result = Struct.new(:new_entries, :proposed_edits, :story_updates,
                             :failure_reason, :error_message, keyword_init: true) do
          def success?
            failure_reason.nil?
          end
        end

        def self.parse(raw)
          unless raw.valid_encoding?
            return failure(:invalid_encoding, "response contains invalid byte sequences for its encoding")
          end

          if raw.bytesize > MAX_RESPONSE_BYTES
            return failure(:response_too_large,
                            "response is #{raw.bytesize} bytes, exceeds the #{MAX_RESPONSE_BYTES}-byte limit")
          end

          # Normalise Windows line endings up front — every downstream ^/$
          # anchored regex assumes bare \n, and a stray \r would otherwise
          # get captured as trailing garbage in headings/field values.
          raw = raw.gsub(/\r\n?/, "\n")

          unless SECTION_HEADERS.values.any? { |header| raw.include?(header) }
            return failure(:missing_markers,
                            "response contains none of the three required section markers")
          end

          sections       = split_top_sections(raw)
          new_entries    = parse_new_entries(sections[:new_entries])
          proposed_edits = parse_proposed_edits(sections[:proposed_edits])
          story_updates  = parse_story_updates(sections[:story_updates])

          total_cards = new_entries.length + proposed_edits.length + story_updates.length
          if total_cards > MAX_CARDS
            return failure(:too_many_cards, "response produced #{total_cards} cards, exceeds #{MAX_CARDS}")
          end

          if (new_entries + proposed_edits + story_updates).any? { |card| field_too_long?(card) }
            return failure(:field_too_long, "a card field exceeds #{MAX_FIELD_LENGTH} characters")
          end

          Result.new(new_entries: new_entries, proposed_edits: proposed_edits, story_updates: story_updates)
        end

        def self.failure(reason, message)
          Result.new(new_entries: [], proposed_edits: [], story_updates: [],
                     failure_reason: reason, error_message: message)
        end
        private_class_method :failure

        def self.field_too_long?(card)
          card.to_h.any? { |_, v| v.is_a?(String) && v.length > MAX_FIELD_LENGTH }
        end
        private_class_method :field_too_long?

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

            sections[key] = content_text.upcase == "NOTHING TO ADD" ? "" : content_text
          end
          sections
        end
        private_class_method :split_top_sections

        # Splits on ### file-label headers, resolves each label to a
        # canonical section key (an unresolvable label rejects that entire
        # label group, logged, not fatal to the call), then splits each
        # label's content into individual ## entries — one NewBibleEntry per
        # entry, not one per file section, so the review UI can accept/skip
        # them individually.
        def self.parse_new_entries(raw)
          return [] if raw.strip.empty?

          parts = raw.split(FILE_LABEL_HEADER)
          return [] if parts.length <= 1

          entries = []
          i = 1
          while i < parts.length - 1
            section_key = resolve_section_key(parts[i])
            content     = parts[i + 1] ? parts[i + 1].strip : ""
            i += 2

            next if section_key.nil?
            next if content.empty? || content.upcase == "NOTHING TO ADD"

            split_into_entries(content).each do |entry_content|
              next unless entry_content.start_with?("## ")
              heading = entry_content.lines.first.to_s.delete_prefix("## ").strip
              entries << NewBibleEntry.new(id: nil, section_key: section_key, heading: heading, content: entry_content)
            end
          end

          entries.each_with_index.map { |entry, idx| entry.with(id: "new_entry_#{idx}") }
        end
        private_class_method :parse_new_entries

        def self.split_into_entries(content)
          content.split(/(?=^## )/).map(&:strip).reject(&:empty?)
        end
        private_class_method :split_into_entries

        def self.resolve_section_key(raw_label)
          normalized = raw_label.strip.downcase.delete_suffix(".md").gsub("_", " ")
          FILE_LABEL_TO_KEY[normalized]
        end
        private_class_method :resolve_section_key

        # Every one of ENTRY/FILE/CURRENT/PROPOSED/REASON is required —
        # stricter than Python's original (which only checked ENTRY) per the
        # review's "stricter parsing" hardening request. A block missing any
        # field, or whose FILE doesn't resolve to a canonical section key, is
        # rejected rather than becoming a partially-populated card.
        def self.parse_proposed_edits(raw)
          blocks = parse_keyed_blocks(raw, %w[ENTRY FILE CURRENT PROPOSED REASON])

          edits = blocks.filter_map do |fields|
            next if %w[entry file current proposed reason].any? { |key| fields[key].to_s.strip.empty? }

            section_key = resolve_section_key(fields["file"])
            next if section_key.nil?

            ProposedBibleEdit.new(id: nil, entry: fields["entry"], section_key: section_key,
                                   current: fields["current"], proposed: fields["proposed"], reason: fields["reason"])
          end

          edits.each_with_index.map { |edit, idx| edit.with(id: "proposed_edit_#{idx}") }
        end
        private_class_method :parse_proposed_edits

        def self.parse_story_updates(raw)
          blocks = parse_keyed_blocks(raw, %w[TYPE UPDATE])

          updates = blocks.filter_map do |fields|
            next if fields["type"].to_s.strip.empty? || fields["update"].to_s.strip.empty?
            StoryUpdate.new(id: nil, type: fields["type"], update: fields["update"])
          end

          updates.each_with_index.map { |update, idx| update.with(id: "story_update_#{idx}") }
        end
        private_class_method :parse_story_updates

        # Splits `raw` on blank-line-separated blocks, then within each block
        # parses KEY: value fields with continuation-line support (a matched
        # "KEY:" line starts a new field; an unmatched line extends the
        # current field's value) — same shape Python's parser uses for both
        # proposed edits and story updates. Returns an array of
        # string-keyed (lowercase key name) hashes, one per block.
        def self.parse_keyed_blocks(raw, keys)
          return [] if raw.strip.empty?

          key_pattern = KEYED_FIELD_PATTERN.call(keys)

          raw.strip.split(/\n{2,}/).filter_map do |block|
            next if block.strip.empty?

            fields        = {}
            current_key   = nil
            current_lines = []

            block.each_line(chomp: true) do |line|
              if (match = key_pattern.match(line))
                fields[current_key] = current_lines.join("\n").strip if current_key
                current_key   = match[1].downcase
                current_lines = [ match[2] ]
              elsif current_key
                current_lines << line
              end
            end
            fields[current_key] = current_lines.join("\n").strip if current_key

            fields
          end
        end
        private_class_method :parse_keyed_blocks
      end
    end
  end
end
