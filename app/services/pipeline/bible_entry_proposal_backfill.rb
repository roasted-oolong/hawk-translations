# ---------------------------------------------------------------------------
# Pipeline::BibleEntryProposalBackfill
#
# Group D1 of docs/PREREAD_STAGING_DESIGN.md: reconciles a novel's current
# bible/*.md pending findings — BibleMarkdownParser#pending_entries, the
# legacy file-vs-DB diff — into real bible_entry_proposals rows, so the old
# diffing apparatus can be deleted (Group D2) without losing whatever
# genuinely-new-or-changed content it was still tracking. Run once per
# novel via `rake bible:backfill_proposals[novel_id]`; a human then
# resolves the backfilled rows through the normal /preread_review UI —
# this class only stages them, it never approves or skips anything itself.
#
# Chapter attribution has no batch context to lean on here (unlike
# Pipeline::BibleEntryProposalIngester's per-preread-run attribution) —
# these entries accumulated across however many past preread/bible_build
# runs actually wrote them. An entry's own parsed first_appearance_chapter
# wins when it names a real Chapter row; otherwise it falls back to the
# novel's own most recent chapter ("as of everything read so far"), the
# same "as of chapter N" spirit as the live ingester's batch.max fallback,
# just without a batch to take N from. A novel with no Chapter rows at all
# has nothing to attribute to — that entry is skipped, not raised on, and
# counted separately so the caller can report it.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleEntryProposalBackfill
    Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

    def initialize(novel, ingester: Pipeline::BibleEntryProposalIngester.new(novel))
      @novel    = novel
      @parser   = BibleMarkdownParser.new(novel)
      @ingester = ingester
    end

    def call
      created = 0
      updated = 0
      skipped = 0

      BibleMarkdownParser::CATEGORIES.each do |category|
        entry_type = Pipeline::BibleEntryProposalIngester::SECTION_TO_ENTRY_TYPE.fetch(category)

        @parser.pending_entries[category].each do |entry|
          chapter = attribute_chapter(entry)
          unless chapter
            skipped += 1
            next
          end

          existed = @novel.bible_entry_proposals.exists?(entry_type: entry_type, korean_key: entry[:korean_key])
          @ingester.upsert_proposal(entry_type, entry, chapter)
          existed ? (updated += 1) : (created += 1)
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped)
    end

    private

    def attribute_chapter(entry)
      candidate = entry[:first_appearance_chapter]
      if candidate
        chapter = @novel.chapters.find_by(number: candidate)
        return chapter if chapter
      end

      last_number = @novel.chapters.maximum(:number)
      last_number && @novel.chapters.find_by(number: last_number)
    end
  end
end
