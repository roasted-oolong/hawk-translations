class RestructureBibleCulturalPhrasesForKoreanIdentity < ActiveRecord::Migration[8.1]
  def up
    # One true duplicate pair existed before this migration: ids 48 and 119,
    # both novel_id=1's "닝겐 (人間 — from Japanese)" — identical content
    # (literal_translation/intended_meaning/context/notes all byte-equal),
    # created ~16 minutes apart. id 119 only exists because a later preread
    # re-parse produced "닝겐" where id 48's original English label was
    # "Ningen" — matched neither by Korean (mismatched romanisation-derived
    # spacing at the time) nor by English (deliberately different string) —
    # the exact bug this migration's Korean-uniqueness constraint closes.
    # Confirmed with the user before deleting: keep the earlier row, drop
    # the later duplicate and its now-orphaned search embedding
    # (bible_embeddings rows are never cascade-cleaned on delete anywhere in
    # this app today — matching existing behavior, not a new gap).
    execute <<~SQL
      DELETE FROM bible_embeddings
      WHERE embeddable_type = 'BibleCulturalPhrase' AND embeddable_id = 119
    SQL
    execute "DELETE FROM bible_cultural_phrases WHERE id = 119"

    # korean_phrase becomes the identity — confirmed via a pre-migration data
    # check that every existing row across all novels already has one (0
    # blank) and, after the dedup above, none collide, so this is a
    # same-migration NOT NULL + unique index, not a backfill-then-constrain
    # two-step.
    change_column_null :bible_cultural_phrases, :korean_phrase, false
    add_index :bible_cultural_phrases, [ :novel_id, :korean_phrase ], unique: true

    # Replaces the single required "phrase" (English label) and optional
    # "established_translation" with a list of {context, translation} pairs.
    # Cultural phrases often have several correct renderings depending on
    # context, and forcing one answer at cataloging time — before any
    # chapter has actually been translated — produced garbage: checked this
    # novel's existing data before writing this migration, and every one of
    # its 77 rows had phrase == korean_phrase (nothing but a copy of the
    # Korean text; the LLM had no scene context to draw an English label
    # from) and not one had established_translation ever filled in. Nothing
    # worth preserving from either dropped column. See docs/DECISIONS.md.
    add_column :bible_cultural_phrases, :translation_examples, :jsonb, null: false, default: []

    remove_column :bible_cultural_phrases, :phrase
    remove_column :bible_cultural_phrases, :established_translation
  end

  def down
    add_column :bible_cultural_phrases, :phrase, :string
    add_column :bible_cultural_phrases, :established_translation, :string

    execute "UPDATE bible_cultural_phrases SET phrase = korean_phrase"
    change_column_null :bible_cultural_phrases, :phrase, false

    remove_column :bible_cultural_phrases, :translation_examples

    remove_index :bible_cultural_phrases, column: [ :novel_id, :korean_phrase ]
    change_column_null :bible_cultural_phrases, :korean_phrase, true

    # The id=119 duplicate deleted in `up` is not restored — this direction
    # reverses the structure, not the one-time data cleanup.
  end
end
