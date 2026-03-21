# frozen_string_literal: true

# =============================================================================
# Embeddings rake tasks — Milestone 12
#
# rake embeddings:backfill[novel_id]   — enqueue GenerateEmbeddingJob for
#   all bible entries in a novel that have no embedding or a stale one.
#   Idempotent — safe to re-run; skips records whose content_hash is current.
#
# rake embeddings:backfill_all         — runs backfill across every novel.
#
# Usage:
#   rails runner db/import/idols_rewind_bible.rb  # import data first
#   rake embeddings:backfill[1]                    # backfill novel with id=1
#   rake embeddings:backfill_all                   # backfill all novels
#
# Jobs are enqueued into Solid Queue and processed by the background worker.
# Monitor progress via the translation_jobs index or Solid Queue internals.
#
# Note: BIBLE_MODELS is defined inside each task body, not at the top level,
# so it is only evaluated after the :environment task has loaded Rails and the
# model constants are available.
# =============================================================================
namespace :embeddings do
  desc "Enqueue GenerateEmbeddingJob for all stale bible entries in a novel. " \
       "Usage: rake embeddings:backfill[novel_id]"
  task :backfill, [ :novel_id ] => :environment do |_t, args|
    bible_models = [
      BibleCharacter,
      BibleLocation,
      BibleTerminology,
      BibleCulturalPhrase,
      BibleStoryEntry
    ].freeze

    novel_id = args[:novel_id]&.to_i
    abort "Usage: rake embeddings:backfill[novel_id]" unless novel_id&.positive?

    novel = Novel.find_by(id: novel_id)
    abort "Novel with id=#{novel_id} not found." unless novel

    puts "[embeddings:backfill] Novel: #{novel.title} (id=#{novel.id})"
    total_enqueued = 0

    bible_models.each do |klass|
      records = klass.where(novel_id: novel.id)
      puts "  #{klass.name}: #{records.count} records"

      records.each do |record|
        content_hash = Digest::SHA256.hexdigest(record.embeddable_text)
        if BibleEmbedding.stale_for?(record, content_hash)
          GenerateEmbeddingJob.perform_later(klass.name, record.id)
          total_enqueued += 1
        end
      end
    end

    puts "[embeddings:backfill] Enqueued #{total_enqueued} job(s)."
  end

  desc "Enqueue GenerateEmbeddingJob for all stale bible entries across every novel."
  task backfill_all: :environment do
    Novel.find_each do |novel|
      puts "[embeddings:backfill_all] Processing novel: #{novel.title} (id=#{novel.id})"
      Rake::Task["embeddings:backfill"].execute(Rake::TaskArguments.new([:novel_id], [novel.id.to_s]))
      Rake::Task["embeddings:backfill"].reenable
    end
  end
end
