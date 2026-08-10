# ---------------------------------------------------------------------------
# Pipeline::BibleEntryProposalIngester
#
# Owns persistence of one preread batch's classified entries into
# bible_entry_proposals, plus the chapter-attribution decision the staging
# table's chapter_id FK requires. Depends on Pipeline::BibleEntryMatcher for
# parsing/classification; never does that work itself. See
# docs/PREREAD_STAGING_DESIGN.md and its "gap #1" chapter-attribution
# writeup.
#
# Input/output shape mirrors Pipeline::PrereadBibleWriter#write_batch
# (plural section keys from PrereadRunner::ResponseParser, a
# :written/:no_new_entries/:empty status per section) so PrereadRunner can
# swap one writer for the other with minimal changes (see the design doc's
# Group B5). Internally translates plural section keys to
# BibleEntryProposal's singular entry_type vocabulary — the wire format is
# legacy, the persisted domain vocabulary isn't.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleEntryProposalIngester
    SECTION_TO_ENTRY_TYPE = {
      characters:       "character",
      locations:        "location",
      terminology:      "terminology",
      cultural_phrases: "cultural_phrase",
      story:            "story"
    }.freeze

    def initialize(novel, matcher: Pipeline::BibleEntryMatcher.new(novel))
      @novel   = novel
      @matcher = matcher
    end

    # parsed_sections: hash of section key => raw markdown content string
    # for one preread batch (Pipeline::Ruby::PrereadRunner::ResponseParser's
    # output shape). batch_nums: the chapter numbers this batch's LLM call
    # covered — used for chapter attribution.
    def ingest_batch(parsed_sections, batch_nums)
      SECTION_TO_ENTRY_TYPE.each_key.to_h do |section|
        content = parsed_sections[section]
        [ section, (content && !content.strip.empty?) ? ingest_section(section, content, batch_nums) : :empty ]
      end
    end

    # find_or_initialize_by + save is the primary idempotency mechanism —
    # ingesting the same entry twice (a re-run, or two batches' ranges
    # overlapping) updates the one existing pending row instead of creating
    # a duplicate. The unique index on [novel_id, entry_type, korean_key] is
    # the concurrency safety net for two ingestions racing on the same
    # novel; RecordNotUnique means the other process's insert won the race
    # between our find and our save, so we re-find and update instead of
    # failing the batch.
    #
    # Public (not just #ingest_batch's own private helper) — chapter
    # attribution is the caller's job, not this method's, so anything that
    # already knows which chapter an entry belongs to can persist it the
    # same way #ingest_batch does. Pipeline::BibleEntryProposalBackfill
    # (Group D1) is the other caller: it classifies via
    # BibleMarkdownParser#pending_entries instead of a preread batch and
    # has its own (simpler, no batch_nums) chapter-attribution rule.
    def upsert_proposal(entry_type, entry, chapter)
      proposal = @novel.bible_entry_proposals.find_or_initialize_by(entry_type: entry_type, korean_key: entry[:korean_key])
      assign_proposal_attrs(proposal, entry, chapter)
      proposal.save!
    rescue ActiveRecord::RecordNotUnique
      proposal = @novel.bible_entry_proposals.find_by!(entry_type: entry_type, korean_key: entry[:korean_key])
      assign_proposal_attrs(proposal, entry, chapter)
      proposal.save!
    end

    private

    def ingest_section(section, content, batch_nums)
      entries = @matcher.classify(section, content)
      return :no_new_entries if entries.empty?

      entry_type = SECTION_TO_ENTRY_TYPE.fetch(section)
      entries.each { |entry| upsert_proposal(entry_type, entry, attribute_chapter(entry, batch_nums)) }
      :written
    end

    def assign_proposal_attrs(proposal, entry, chapter)
      proposal.assign_attributes(
        chapter:            chapter,
        existing_record_id: entry[:existing_id],
        fields:             entry.except(:korean_key, :is_existing, :existing_id, :field_changes)
      )
    end

    # Preread's one LLM call per batch hands back a whole batch's worth of
    # markdown with no per-entry chapter tag. Per entry, against this
    # batch's own range: a parsed first_appearance_chapter that falls
    # within the batch and has a matching Chapter row wins; otherwise (no
    # chapter field, an out-of-batch value, or story entries, which never
    # parse one) attribute to the batch's last chapter — "as of reading
    # through chapter N."
    def attribute_chapter(entry, batch_nums)
      candidate = entry[:first_appearance_chapter]
      range     = batch_nums.min..batch_nums.max

      if candidate && range.cover?(candidate)
        chapter = @novel.chapters.find_by(number: candidate)
        return chapter if chapter
      end

      @novel.chapters.find_by(number: batch_nums.max)
    end
  end
end
