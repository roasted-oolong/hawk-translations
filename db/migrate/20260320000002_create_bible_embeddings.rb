# frozen_string_literal: true

# =============================================================================
# Milestone 12 — bible_embeddings table
#
# Stores pgvector embeddings and tsvector keyword index for all five bible
# entry types in one place. Polymorphic on (embeddable_type, embeddable_id).
#
# Design decisions:
# - novel_id and organization_id are denormalized FKs for fast scoped filtering
#   without joining back through the embeddable record.
# - content_hash (SHA256 of embeddable_text) guards against re-embedding
#   records whose text has not changed — GenerateEmbeddingJob skips when hash
#   matches.
# - embedding is vector(1024) — Voyage AI voyage-3-lite output dimension.
# - search_text is tsvector — populated by GenerateEmbeddingJob via a direct
#   SQL update using to_tsvector. Covers English + Korean text from the same
#   concatenated embeddable_text source used for the vector embedding.
# - Indexes:
#     ivfflat on embedding — approximate nearest neighbor search (pgvector)
#     GIN on search_text  — keyword/Korean search
#     unique (embeddable_type, embeddable_id) — one row per bible record
#     novel_id            — novel-scoped search filtering
#     organization_id     — cross-novel org-scoped search filtering
# =============================================================================
class CreateBibleEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_embeddings do |t|
      # Polymorphic association — covers all five bible entry types
      t.string  :embeddable_type, null: false
      t.bigint  :embeddable_id,   null: false

      # Denormalized for filtering without joins
      t.references :novel,        null: false, foreign_key: true, index: true
      t.references :organization, null: false, foreign_key: true, index: true

      # Staleness guard — SHA256 of the text that was embedded
      t.string  :content_hash, null: false

      # Voyage AI voyage-3-lite — 1024 dimensions.
      # Use raw SQL type string so PostgreSQL receives vector(1024) with
      # explicit dimensions — required for the ivfflat index below.
      t.column  :embedding, "vector(1024)"

      # tsvector keyword index — populated by GenerateEmbeddingJob
      t.column  :search_text, "tsvector"

      t.timestamps
    end

    # One embedding record per bible record — enforced at DB level
    add_index :bible_embeddings,
              [ :embeddable_type, :embeddable_id ],
              unique: true,
              name: "index_bible_embeddings_on_embeddable"

    # Approximate nearest neighbor search — ivfflat, cosine distance
    # lists: 100 is a sensible default for a corpus of this size;
    # revisit if the table grows beyond ~100k rows.
    add_index :bible_embeddings,
              :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              name: "index_bible_embeddings_on_embedding"

    # GIN index for tsvector keyword/Korean search
    add_index :bible_embeddings,
              :search_text,
              using: :gin,
              name: "index_bible_embeddings_on_search_text"
  end
end
