# ---------------------------------------------------------------------------
# Pipeline::BibleEntryMatcher
#
# Pure (novel, category, raw markdown) -> classified entry hashes. Parses a
# preread-shaped markdown chunk ("## Name (Korean)" heading + "- Field:
# value" bullets) and, when asked to classify, matches each parsed entry
# against that novel's live bible tables by Korean key: brand new (no
# match), changed (matches an existing record with different field values),
# or unchanged (matches with no differences, dropped — nothing to review).
#
# No persistence, no file I/O — BibleMarkdownParser (reading bible/*.md for
# the legacy pending-entries flow) and Pipeline::BibleEntryProposalIngester
# (writing bible_entry_proposals rows from a preread LLM response) both
# wrap this with their own I/O; the parsing/classification logic itself
# lives here exactly once. See docs/PREREAD_STAGING_DESIGN.md.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleEntryMatcher
    COMPARABLE_FIELDS = {
      characters:       %i[name korean_name aliases role physical_description speech_pattern
                           honorifics_used_toward honorifics_they_use relationships
                           first_appearance_chapter notes],
      locations:        %i[name korean_name significance first_appearance_chapter notes],
      terminology:      %i[term korean_term definition usage_notes first_appearance_chapter notes],
      cultural_phrases: %i[korean_phrase literal_translation intended_meaning context
                           first_appearance_chapter notes],
      story:            %i[title content category],
    }.freeze

    STORY_CATEGORY_PATTERNS = [
      [ /main.?plot/i,  "main_plot"   ],
      [ /subplot/i,     "subplot"     ],
      [ /watch.?list/i, "watch_list"  ],
      [ /theme|motif/i, "theme"       ],
    ].freeze

    def initialize(novel)
      @novel = novel
    end

    # ---------------------------------------------------------------------------
    # Public
    # ---------------------------------------------------------------------------

    # Raw parsed entries from markdown content for one category — no
    # dismissed-key filtering, no matching against live records.
    def parse(category, content)
      content
        .split(/\n(?=## )/)
        .map(&:strip)
        .select { |chunk| chunk.start_with?("## ") }
        .map { |chunk| parse_chunk(category, chunk) }
        .compact
    end

    # Parses content and classifies each entry against the novel's live
    # bible tables in one step.
    def classify(category, content)
      classify_parsed(category, parse(category, content))
    end

    # Classifies already-parsed entries — for callers (BibleMarkdownParser)
    # that cache #parse's output and don't want to re-parse for it.
    #
    # Drops anything whose korean_key is already dismissed, and anything
    # that matches an existing record with no actual field differences
    # (nothing to review). Everything else is tagged is_existing: false
    # (brand new) or is_existing: true, existing_id:, field_changes: (a
    # proposed change to an existing record).
    def classify_parsed(category, entries)
      dismissed = dismissed_keys
      fields    = COMPARABLE_FIELDS[category]
      index     = record_index(category)

      entries.filter_map do |entry|
        next if dismissed.include?("#{category}:#{entry[:korean_key]}")
        classify_entry(entry, index.call(entry), fields)
      end
    end

    # The live record (if any) a parsed entry's korean_key/name matches, by
    # the same per-category lookup #classify_parsed uses internally. Public
    # so callers doing their own dismissed-filtering (e.g.
    # BibleMarkdownParser#dismissed_entries_for) don't duplicate this.
    def matching_record(category, entry)
      record_index(category).call(entry)
    end

    private

    # One in-memory index per category, built once and reused across every
    # entry in a batch — matches the original filter_pending's
    # index_by(&:korean_name)/index_by(&:name) shape rather than issuing a
    # query per entry. Memoized per matcher instance, so a matcher used
    # across several #classify/#matching_record calls in one request only
    # loads each category's records once.
    def record_index(category)
      @record_indexes ||= {}
      @record_indexes[category] ||= build_record_index(category)
    end

    def build_record_index(category)
      case category
      when :characters
        by_korean = @novel.bible_characters.index_by(&:korean_name)
        by_name   = @novel.bible_characters.index_by(&:name)
        ->(entry) { by_korean[entry[:korean_key]] || by_name[entry[:name]] }
      when :locations
        by_korean = @novel.bible_locations.index_by(&:korean_name)
        by_name   = @novel.bible_locations.index_by(&:name)
        ->(entry) { by_korean[entry[:korean_key]] || by_name[entry[:name]] }
      when :terminology
        by_korean = @novel.bible_terminologies.index_by(&:korean_term)
        by_name   = @novel.bible_terminologies.index_by(&:term)
        ->(entry) { by_korean[entry[:korean_key]] || by_name[entry[:term]] }
      when :cultural_phrases
        # Korean-only match — no English fallback. See docs/DECISIONS.md
        # 2026-08-08: matching by English string is exactly what produced
        # duplicate rows for the same Korean phrase with different (both
        # legitimate) English rendering choices.
        by_korean = @novel.bible_cultural_phrases.index_by { |r| normalize_key(r.korean_phrase) }
        ->(entry) { by_korean[entry[:korean_key]] }
      when :story
        by_title = @novel.bible_story_entries.index_by(&:title)
        ->(entry) { by_title[entry[:title]] }
      else
        ->(_entry) { nil }
      end
    end

    # ---------------------------------------------------------------------------
    # Entry splitting
    # ---------------------------------------------------------------------------

    def parse_chunk(category, chunk)
      lines = chunk.split("\n")
      heading = lines.shift&.strip
      return nil unless heading&.start_with?("## ")

      category == :story ? parse_story_entry(heading, lines) : parse_structured_entry(category, heading, lines)
    end

    # ---------------------------------------------------------------------------
    # Heading + field parsing
    # ---------------------------------------------------------------------------

    def parse_heading(heading)
      m = heading.match(/\A## (.+?)\s*(?:\((.+)\))?\s*\z/)
      return [ nil, nil ] unless m

      [ m[1].strip, m[2]&.strip ]
    end

    def parse_fields(lines)
      lines.each_with_object({}) do |line, h|
        m = line.match(/\A-\s+(.+?):\s*(.*)\z/)
        next unless m

        key   = m[1].strip.downcase
        value = m[2].strip
        h[key] = value unless value.empty? || value.match?(/\A\[.*\]\z/)
      end
    end

    def extract_chapter(value)
      value.to_s.scan(/\d+/).first&.to_i
    end

    def join_notes(*parts)
      parts.flatten.compact_blank.join("\n").presence
    end

    # ---------------------------------------------------------------------------
    # Per-category parsers
    # ---------------------------------------------------------------------------

    def parse_structured_entry(category, heading, lines)
      name, korean = parse_heading(heading)
      return nil unless name.present?

      fields = parse_fields(lines)

      case category
      when :characters       then parse_character(name, korean, fields)
      when :locations        then parse_location(name, korean, fields)
      when :terminology      then parse_terminology(name, korean, fields)
      when :cultural_phrases then parse_cultural_phrase(name, korean, fields)
      end
    end

    def parse_character(name, korean, f)
      speech = join_notes(f["speech pattern"], f["dialogue cues"])
      notes  = join_notes(
        f["notes"],
        f["story bible reference"].presence&.then { "Bible ref: #{_1}" }
      )

      {
        name:                     name,
        korean_name:              f["korean name"].presence || korean,
        aliases:                  f["aliases/titles"].presence,
        role:                     f["role"].presence,
        physical_description:     f["physical description"].presence,
        speech_pattern:           speech,
        honorifics_used_toward:   f["honorifics used toward them"].presence,
        honorifics_they_use:      f["honorifics they use toward others"].presence,
        relationships:            f["relationships"].presence,
        first_appearance_chapter: extract_chapter(f["first appearance"]),
        notes:                    notes,
        korean_key:               normalize_key(f["korean name"].presence || korean || name),
      }.compact
    end

    def parse_location(name, korean, f)
      notes = f["romanisation"].presence&.then { "Romanisation: #{_1}" }

      {
        name:                     name,
        korean_name:              f["korean name"].presence || korean,
        significance:             f["significance"].presence,
        first_appearance_chapter: extract_chapter(f["first appearance"]),
        notes:                    notes,
        korean_key:               normalize_key(f["korean name"].presence || korean || name),
      }.compact
    end

    def parse_terminology(name, korean, f)
      notes = join_notes(
        f["notes"],
        f["category"].presence&.then { "Category: #{_1}" },
        f["story bible reference"].presence&.then { "Bible ref: #{_1}" }
      )

      {
        term:                     name,
        korean_term:              f["korean term"].presence || korean,
        definition:               f["definition"].presence,
        usage_notes:              f["usage notes"].presence,
        first_appearance_chapter: extract_chapter(f["first appearance"]),
        notes:                    notes,
        korean_key:               normalize_key(f["korean term"].presence || korean || name),
      }.compact
    end

    def parse_cultural_phrase(name, korean, f)
      tn = join_notes(
        f["t/n written"].presence&.then { "T/N written: #{_1}" },
        f["t/n text"].presence&.then   { "T/N text: #{_1}" }
      )
      notes         = join_notes(f["notes"], tn)
      # No English fallback here — see docs/DECISIONS.md 2026-08-08. The
      # heading is Korean-only now (PromptBuilder's template asks for
      # "## [Korean phrase]", nothing else), so `name` is already the Korean
      # phrase text in the common case; `korean`/the explicit field only
      # matter when the LLM still drifts to an annotated heading.
      korean_phrase = f["korean phrase"].presence || korean || name

      {
        korean_phrase:            korean_phrase,
        literal_translation:      f["literal translation"].presence,
        intended_meaning:         f["intended meaning"].presence,
        context:                  f["context"].presence,
        first_appearance_chapter: extract_chapter(f["first appearance"]),
        notes:                    notes,
        korean_key:               normalize_key(korean_phrase),
      }.compact
    end

    def parse_story_entry(heading, lines)
      title   = heading.sub(/\A## /, "").strip
      content = lines.reject { |l| l.strip == "---" }.join("\n").strip

      return nil if content.blank?

      {
        title:      title,
        content:    content,
        category:   infer_story_category(title),
        korean_key: normalize_key(title),
      }.compact
    end

    # Single point through which every korean_key is derived, so preread's
    # per-entry identity — what gets stored in preread_dismissed_keys, and
    # what a re-parse compares against it — is stable across runs even when
    # the LLM's raw rendering drifts (whitespace, full/half-width chars,
    # Latin casing). Without this, "skip" quietly stops being permanent: a
    # later preread run re-derives a different key for the same underlying
    # term, the old dismissal no longer matches, and the entry reappears in
    # the review queue — usually with a new English rendering too, which is
    # what makes it look like a different suggestion rather than a repeat.
    def normalize_key(str)
      Pipeline::BibleUtils.normalize_korean(str)
    end

    def infer_story_category(title)
      STORY_CATEGORY_PATTERNS.each { |pat, cat| return cat if title.match?(pat) }
      "world_building"
    end

    # ---------------------------------------------------------------------------
    # Classification
    # ---------------------------------------------------------------------------

    def dismissed_keys
      @dismissed_keys ||= JSON.parse(@novel.preread_dismissed_keys || "[]")
    rescue JSON::ParserError
      []
    end

    def classify_entry(entry, record, fields)
      return entry.merge(is_existing: false) if record.nil?

      changes = compute_field_changes(entry, record, fields)
      return nil if changes.empty?

      entry.merge(is_existing: true, existing_id: record.id, field_changes: changes)
    end

    def compute_field_changes(entry, record, fields)
      fields.each_with_object({}) do |field, h|
        new_val = normalize_compare(entry[field])
        old_val = normalize_compare(record.respond_to?(field) ? record.public_send(field) : nil)
        next if new_val == old_val
        h[field] = { was: old_val, now: new_val }
      end
    end

    def normalize_compare(val)
      return nil if val.nil?
      val.to_s.strip.presence
    end
  end
end
