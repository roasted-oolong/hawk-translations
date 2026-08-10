# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Pipeline::BibleEntryDocWriter
#
# Formats one novel's current rows for a single bible category into that
# category's bible/*.md file — the file PromptBuilder actually reads via
# NOVEL_FILES. Mirrors RenderingRuleDocWriter's proven shape: deliberately
# dumb about where the rows came from (the DB is the source of truth, this
# class only knows how to render a given list of records into one file),
# fully rewriting it on every #write rather than patching in place, so the
# file can never drift from what the DB currently holds (see
# docs/PREREAD_STAGING_DESIGN.md, Part 3).
#
# One class parameterized by category rather than five, since the shape
# (header, "## heading (Korean)" per entry, "- Field: value" lines, "---"
# separators) is identical across categories — only which fields and what
# the heading looks like differ.
#
# Unlike RenderingRuleDocWriter, this class's output is also read back by
# Pipeline::BibleEntryMatcher — the preread/backfill ingestion path
# reclassifies a fresh parse of this file against these same live tables.
# Every Pipeline::BibleEntryMatcher::COMPARABLE_FIELDS value is written so
# that a same-second re-parse reports no field_changes for an untouched
# record; see #flatten for the one known narrower exception (multi-line
# notes).
# ---------------------------------------------------------------------------
module Pipeline
  class BibleEntryDocWriter
    HEADER_TITLE = {
      characters:       "Character Bible",
      locations:        "Locations",
      terminology:      "Terminology",
      cultural_phrases: "Cultural Phrases",
      story:            "Story Bible"
    }.freeze

    # category -> bible/*.md filename. Formerly BibleMarkdownParser::FILE_MAP
    # (deleted in docs/PREREAD_STAGING_DESIGN.md's Group D2) — this class is
    # the sole remaining writer of these files, so it's the natural owner of
    # the mapping now.
    FILE_MAP = {
      characters:       "characters.md",
      locations:        "locations.md",
      terminology:      "terminology.md",
      cultural_phrases: "cultural_phrases.md",
      story:            "story.md",
    }.freeze

    def initialize(novel_dir, category)
      @novel_dir = novel_dir
      @category  = category
    end

    # Given no records, removes the file (if any) rather than leaving an
    # empty "# Character Bible" shell behind — matches
    # RenderingRuleDocWriter#write's same no-rules behavior.
    def write(records)
      return if @novel_dir.blank?

      if records.empty?
        File.delete(path) if File.exist?(path)
        return
      end

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, format_file(records))
    end

    private

    def path
      File.join(@novel_dir, "bible", FILE_MAP.fetch(@category))
    end

    def format_file(records)
      header   = "# #{HEADER_TITLE.fetch(@category)}\nLast Updated: #{Date.current.iso8601}"
      sections = [ header ] + records.map { |record| format_entry(record) }
      sections.join("\n\n---\n\n") + "\n"
    end

    def format_entry(record)
      case @category
      when :characters       then format_character(record)
      when :locations        then format_location(record)
      when :terminology      then format_terminology(record)
      when :cultural_phrases then format_cultural_phrase(record)
      when :story            then format_story(record)
      end
    end

    # ---------------------------------------------------------------------
    # Per-category formatting. Field labels are chosen to match the exact
    # (case-insensitive) keys Pipeline::BibleEntryMatcher#parse_fields
    # expects for every Pipeline::BibleEntryMatcher::COMPARABLE_FIELDS
    # entry, plus any remaining real DB columns for human readability
    # (harmless extras the matcher simply doesn't look for).
    # ---------------------------------------------------------------------

    def format_character(r)
      [
        heading(r.name, r.korean_name),
        field("Korean name", r.korean_name),
        field("Aliases/Titles", r.aliases),
        field("First appearance", r.first_appearance_chapter),
        field("Last Updated", display_date(r.last_updated_at)),
        field("Role", r.role),
        field("Significance", r.significance),
        field("Physical description", r.physical_description),
        field("Speech pattern", r.speech_pattern),
        field("Honorifics used toward them", r.honorifics_used_toward),
        field("Honorifics they use toward others", r.honorifics_they_use),
        field("Relationships", r.relationships),
        field("Notes", r.notes)
      ].compact.join("\n")
    end

    def format_location(r)
      [
        heading(r.name, r.korean_name),
        field("Korean name", r.korean_name),
        field("Type", r.location_type),
        field("First appearance", r.first_appearance_chapter),
        field("Last Updated", display_date(r.last_updated_at)),
        field("Description", r.description),
        field("Significance", r.significance),
        field("Notes", r.notes)
      ].compact.join("\n")
    end

    def format_terminology(r)
      [
        heading(r.term, r.korean_term),
        field("Korean term", r.korean_term),
        field("First appearance", r.first_appearance_chapter),
        field("Last Updated", display_date(r.last_updated_at)),
        field("Definition", r.definition),
        field("Usage notes", r.usage_notes),
        field("Notes", r.notes)
      ].compact.join("\n")
    end

    # Korean-only heading, no English label/parenthetical — korean_phrase
    # is the sole identity (docs/DECISIONS.md, 2026-08-08 "cultural phrases:
    # Korean identity, no forced English label").
    def format_cultural_phrase(r)
      [
        "## #{r.korean_phrase}",
        field("Literal translation", r.literal_translation),
        field("Intended meaning", r.intended_meaning),
        field("Context", r.context),
        field("First appearance", r.first_appearance_chapter),
        field("Last Updated", display_date(r.last_updated_at)),
        translation_examples_block(r),
        field("Notes", r.notes)
      ].compact.join("\n")
    end

    def format_story(r)
      [
        "## #{r.title}",
        r.content.to_s.strip
      ].reject(&:blank?).join("\n\n")
    end

    # ---------------------------------------------------------------------
    # Shared helpers
    # ---------------------------------------------------------------------

    def heading(name, korean)
      korean.present? ? "## #{name} (#{korean})" : "## #{name}"
    end

    # nil when value is blank, so callers can .compact it away entirely
    # rather than writing a dangling "- Field: " line — the matcher treats
    # an empty value the same either way, but an omitted line reads cleaner
    # for humans browsing the file.
    def field(label, value)
      return nil if value.blank?

      "- #{label}: #{flatten(value)}"
    end

    # Collapses embedded newlines/runs of whitespace to a single space.
    # Pipeline::BibleEntryMatcher#parse_fields only recognizes "- Key:
    # value" as a single physical line, so a multi-paragraph note (possible
    # today — notes are a plain <textarea>) has to be flattened to survive
    # at all. Known, permanent limitation this accepts: re-parsing a
    # flattened multi-paragraph note no longer byte-matches the DB's real
    # (newline-containing) value, so a live preread/backfill pass over this
    # file can keep reporting a spurious "changed" diff for that one field.
    # Preferable to the alternative, which is dropping the edit from the
    # file completely.
    def flatten(value)
      value.to_s.gsub(/\s+/, " ").strip
    end

    def display_date(timestamp)
      timestamp&.to_date&.iso8601
    end

    # translation_examples has no legacy parser field to match against (it
    # didn't exist before the field itself did — see docs/DECISIONS.md,
    # 2026-08-08 migration entry) so nothing here needs to round-trip; it's
    # written purely so an edit to a cultural phrase's examples actually
    # reaches the translation prompt at all, which is exactly the drift bug
    # this class exists to close. Indented, undashed lines are invisible to
    # #parse_fields (which only matches lines starting "- "), so they can't
    # be misread as separate fields.
    def translation_examples_block(r)
      return nil unless r.respond_to?(:translation_examples) && r.translation_examples.present?

      lines = r.translation_examples.map { |ex|
        ctx = ex["context"].presence
        tr  = ex["translation"]
        "  - #{ctx ? "#{ctx}: #{tr}" : tr}"
      }
      ([ "- Translation examples:" ] + lines).join("\n")
    end
  end
end
