# frozen_string_literal: true

# =============================================================================
# Bible rake tasks
#
# rake bible:backfill_proposals[novel_id]  — reconcile one novel's current
#   bible/*.md pending findings (BibleMarkdownParser#pending_entries, the
#   legacy file-vs-DB diff) into real bible_entry_proposals rows. Group D1
#   of docs/PREREAD_STAGING_DESIGN.md — a one-time step ahead of D2 deleting
#   BibleMarkdownParser/Pipeline::PrereadBibleWriter, so nothing that
#   diffing was still tracking gets silently lost. Idempotent — safe to
#   re-run; find_or_initialize_by means a second run updates rather than
#   duplicates.
#
# rake bible:backfill_proposals_all        — runs the above across every
#   novel.
#
# Neither task approves or skips anything — a human resolves the
# backfilled proposals afterward through the normal /preread_review UI.
# =============================================================================
namespace :bible do
  desc "Backfill one novel's pending bible/*.md findings into bible_entry_proposals. " \
       "Usage: rake bible:backfill_proposals[novel_id]"
  task :backfill_proposals, [ :novel_id ] => :environment do |_t, args|
    novel_id = args[:novel_id]&.to_i
    abort "Usage: rake bible:backfill_proposals[novel_id]" unless novel_id&.positive?

    novel = Novel.find_by(id: novel_id)
    abort "Novel with id=#{novel_id} not found." unless novel

    run_backfill(novel)
  end

  desc "Backfill pending bible/*.md findings into bible_entry_proposals for every novel."
  task backfill_proposals_all: :environment do
    Novel.find_each { |novel| run_backfill(novel) }
  end

  def run_backfill(novel)
    result = Pipeline::BibleEntryProposalBackfill.new(novel).call
    puts "[bible:backfill_proposals] #{novel.title} (id=#{novel.id}): " \
         "#{result.created} created, #{result.updated} updated, #{result.skipped} skipped (no chapter to attribute to)."
  end
end
