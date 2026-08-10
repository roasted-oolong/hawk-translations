class CreateBibleEntryProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_entry_proposals do |t|
      t.references :novel,   null: false, foreign_key: true
      t.references :chapter, null: false, foreign_key: true
      t.string  :entry_type,         null: false   # "character" | "location" | "terminology" | "cultural_phrase" | "story"

      # Nullable, no real FK: nil means "brand-new entry"; set means "proposed
      # change to an existing row." Not a polymorphic belongs_to — entry_type's
      # vocabulary doesn't line up with any single _type column across the 5
      # differently-pluralized bible tables, so resolution goes through
      # BibleEntryProposal::ENTRY_TYPE_TO_ASSOCIATION instead.
      t.bigint  :existing_record_id
      t.string  :korean_key,         null: false
      t.jsonb   :fields,             null: false, default: {}

      # Single-value in practice today ("pending" only — resolved rows are
      # deleted, not archived, per docs/PREREAD_STAGING_DESIGN.md). Kept as a
      # column per the design doc's own schema table — self-documenting, not
      # evidence more statuses are coming.
      t.string  :status,             null: false, default: "pending"

      t.timestamps
    end

    # Makes ingestion idempotent across overlapping preread runs before a
    # human reviews anything: find_or_initialize_by is the primary mechanism,
    # this index is the concurrency safety net if two jobs race on the same
    # novel (rescue ActiveRecord::RecordNotUnique, retry as update).
    add_index :bible_entry_proposals, [ :novel_id, :entry_type, :korean_key ], unique: true,
      name: "index_bible_entry_proposals_on_novel_type_and_key"
  end
end
