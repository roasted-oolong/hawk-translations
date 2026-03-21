# frozen_string_literal: true

# =============================================================================
# GenerateEmbeddingJob
#
# Generates and upserts a Voyage AI embedding for a single bible entry record.
# Enqueued by the Embeddable concern after every save on the five bible models.
#
# Parameters
# ----------
# embeddable_type : String
#   ActiveRecord model name — "BibleCharacter", "BibleLocation", etc.
# embeddable_id : Integer
#   Primary key of the record to embed.
#
# Lifecycle
# ---------
# 1. Look up the record. If deleted (race condition), return silently.
# 2. Compute SHA256 of embeddable_text.
# 3. Check BibleEmbedding.stale_for? — skip if content unchanged.
# 4. Call VoyageClient.embed to get the vector.
# 5. Upsert BibleEmbedding with the new vector, hash, and search_text.
#
# The upsert sets search_text via a raw SQL to_tsvector expression so the
# tsvector is always derived from the same text as the embedding, without
# a separate update round-trip.
#
# Errors
# ------
# VoyageClient::ApiError and VoyageClient::ConfigurationError are re-raised
# so Solid Queue's retry mechanism handles transient failures (rate limits,
# network timeouts).
# =============================================================================
class GenerateEmbeddingJob < ApplicationJob
  queue_as :default

  def perform(embeddable_type, embeddable_id)
    klass  = embeddable_type.constantize
    record = klass.find_by(id: embeddable_id)

    # Record deleted between save and job execution — nothing to do.
    return if record.nil?

    text         = record.embeddable_text
    content_hash = Digest::SHA256.hexdigest(text)

    # Skip API call if content has not changed since last embedding.
    return unless BibleEmbedding.stale_for?(record, content_hash)

    vector = VoyageClient.embed(text)

    upsert_embedding(record, vector, content_hash, text)
  end

  private

  def upsert_embedding(record, vector, content_hash, text)
    # Use upsert_all for atomic insert-or-update on the unique index
    # (embeddable_type, embeddable_id). The search_text tsvector is computed
    # by PostgreSQL from the same text string so it stays in sync with the
    # embedding without a second query.
    now = Time.current

    BibleEmbedding.upsert(
      {
        embeddable_type: record.class.name,
        embeddable_id:   record.id,
        novel_id:        record.novel_id,
        organization_id: record.novel.organization_id,
        content_hash:    content_hash,
        embedding:       "[#{vector.join(",")}]",
        search_text:     Arel.sql("to_tsvector('simple', #{ActiveRecord::Base.connection.quote(text)})"),
        created_at:      now,
        updated_at:      now
      },
      unique_by: %i[embeddable_type embeddable_id],
      update_only: %i[content_hash embedding search_text]
    )
  end
end
