# frozen_string_literal: true

# =============================================================================
# BibleEmbedding
#
# One row per bible entry record. Stores:
# - embedding: vector(1024) from Voyage AI voyage-3-lite
# - search_text: tsvector for keyword/Korean text search
# - content_hash: SHA256 of embeddable_text — used by GenerateEmbeddingJob
#   to skip re-embedding records whose content has not changed
#
# Polymorphic on (embeddable_type, embeddable_id), covering all five bible
# entry types. novel_id and organization_id are denormalized for efficient
# scoped queries without joining back through the embeddable record.
#
# The table is write-only from the Rails model layer except via upsert in
# GenerateEmbeddingJob. Never build or save BibleEmbedding records directly
# in application code — always go through GenerateEmbeddingJob.
# =============================================================================
class BibleEmbedding < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :embeddable, polymorphic: true
  belongs_to :novel
  belongs_to :organization

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :embeddable_type, presence: true
  validates :embeddable_id,   presence: true
  validates :content_hash,    presence: true
  validates :embeddable_id,
            uniqueness: { scope: :embeddable_type,
                          message: "already has an embedding record" }

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  # Filter to embeddings for a specific novel — used by BibleSearchService
  # for novel-scoped searches.
  scope :for_novel, ->(novel) { where(novel: novel) }

  # Filter to embeddings for an entire organization — used by BibleSearchService
  # for cross-novel org-scoped searches.
  scope :for_organization, ->(org) { where(organization: org) }

  # Filter by embeddable type — allows callers to restrict search to specific
  # bible categories (e.g. characters only, or characters + locations).
  # Accepts an array of model name strings: ["BibleCharacter", "BibleLocation"]
  scope :for_categories, ->(types) { where(embeddable_type: types) }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Returns true if no embedding exists for the record, or if the existing
  # embedding's content_hash differs from the given hash.
  # Used by GenerateEmbeddingJob to avoid unnecessary Voyage AI API calls.
  def self.stale_for?(embeddable, content_hash)
    existing = find_by(embeddable_type: embeddable.class.name, embeddable_id: embeddable.id)
    existing.nil? || existing.content_hash != content_hash
  end
end
