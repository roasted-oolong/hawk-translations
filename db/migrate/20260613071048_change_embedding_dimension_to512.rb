# frozen_string_literal: true

# voyage-3-lite produces 512-dimensional vectors, not 1024. The original
# migration set vector(1024) based on an incorrect assumption. The table was
# empty so no data needs backfilling.
class ChangeEmbeddingDimensionTo512 < ActiveRecord::Migration[8.1]
  def up
    # ivfflat index must be dropped before changing the column type.
    remove_index :bible_embeddings, name: "index_bible_embeddings_on_embedding"
    change_column :bible_embeddings, :embedding, "vector(512)"
    add_index :bible_embeddings,
              :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              name: "index_bible_embeddings_on_embedding"
  end

  def down
    remove_index :bible_embeddings, name: "index_bible_embeddings_on_embedding"
    change_column :bible_embeddings, :embedding, "vector(1024)"
    add_index :bible_embeddings,
              :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              name: "index_bible_embeddings_on_embedding"
  end
end
