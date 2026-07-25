# ---------------------------------------------------------------------------
# Pipeline::BibleReviewWriter
#
# The sole code path that decides *what* bible-file mutation a
# post_translation_review card requires. Performs no file I/O, locking, or
# atomic-write logic itself — every write goes through Pipeline::BibleFileEditor
# (shared with Pipeline::PrereadBibleWriter/R6), which owns the
# lock -> fresh-read -> revalidate -> atomic-write mechanics. This class only
# ever sees a card and returns what happened to it; PostTranslationReviewController
# decides which cards get committed (only "accepted"/"accepted_revised" ones)
# and records each outcome back onto the job.
#
# card is a plain hash with string keys, as stored in a TranslationJob's
# result_payload (post JSON round-trip) — see
# Pipeline::Ruby::PostTranslationReview::ResponseParser's #to_card_hash for
# the shape each card_type produces.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleReviewWriter
    SECTION_TO_FILE = {
      "characters"       => "bible/characters.md",
      "locations"        => "bible/locations.md",
      "terminology"      => "bible/terminology.md",
      "cultural_phrases" => "bible/cultural_phrases.md",
      "story"            => "bible/story.md"
    }.freeze

    def initialize(novel_dir, editor: Pipeline::BibleFileEditor.new)
      @novel_dir = novel_dir
      @editor    = editor
    end

    # Returns one of :applied, :skipped_not_found, :skipped_ambiguous,
    # :skipped_duplicate, :skipped_unresolved_file, :skipped_unknown_card_type.
    def commit(card)
      case card["card_type"]
      when "proposed_edit" then commit_edit(card)
      when "new_entry"     then commit_new_entry(card)
      when "story_update"  then commit_story_update(card)
      else
        :skipped_unknown_card_type
      end
    end

    private

    # Locks only the one file this card targets, re-reads it fresh under the
    # lock, and requires `current` to match exactly once — zero and multiple
    # matches are both skips, with distinguishable reasons (BibleFileEditor's
    # own contract, unmodified here).
    def commit_edit(card)
      file = resolve_file(card["section_key"])
      return :skipped_unresolved_file unless file

      @editor.replace(file, current: card["current"], proposed: card["proposed"])
    end

    # Dedup key is the card's own heading, checked against the freshly-read
    # file's existing heading keys — never the proposal-generation-time
    # snapshot the card was built from.
    def commit_new_entry(card)
      file = resolve_file(card["section_key"])
      return :skipped_unresolved_file unless file

      result = @editor.append_block(file) do |fresh|
        existing_keys = Pipeline::BibleUtils.extract_heading_keys(fresh)
        entry_keys    = Pipeline::BibleUtils.extract_heading_keys(card["content"])

        next Pipeline::BibleFileEditor::SKIP if entry_keys.any? && !(entry_keys & existing_keys).empty?

        append(fresh, card["content"])
      end

      outcome_for(result)
    end

    # Story updates have no section_key of their own — every one targets
    # story.md, matching the prompt's own "TYPE:/UPDATE:" format (no FILE:
    # field). Dedup is exact-text match against the freshly-read file, the
    # same lexical-not-semantic limitation heading-key dedup already accepts.
    def commit_story_update(card)
      file      = resolve_file("story")
      formatted = "**#{card['type']}** — #{card['update']}"

      result = @editor.append_block(file) do |fresh|
        next Pipeline::BibleFileEditor::SKIP if fresh.include?(formatted)

        append(fresh, formatted)
      end

      outcome_for(result)
    end

    def outcome_for(result)
      result == Pipeline::BibleFileEditor::SKIP ? :skipped_duplicate : :applied
    end

    def append(fresh, content)
      separator = fresh.strip.empty? ? "" : "\n\n---\n\n"
      "#{fresh.rstrip}#{separator}#{content.strip}\n"
    end

    def resolve_file(section_key)
      relative = SECTION_TO_FILE[section_key]
      relative && File.join(@novel_dir, relative)
    end
  end
end
