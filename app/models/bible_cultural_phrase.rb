# frozen_string_literal: true

# =============================================================================
# BibleCulturalPhrase
#
# Identity is korean_phrase, not an English label — see docs/DECISIONS.md
# (2026-08-08, "cultural phrases: Korean identity, no forced English label").
# A cultural phrase's correct English rendering is often context-dependent
# (the same idiom lands differently depending on tone/scene), so unlike
# characters/locations/terminology this model deliberately has no single
# canonical English field to require. `translation_examples` holds however
# many {context, translation} pairs have actually been decided at real
# translation time, rather than forcing one guess at cataloging time.
# =============================================================================
class BibleCulturalPhrase < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Concerns
  # ---------------------------------------------------------------------------
  include Embeddable
  include BibleDocSynced

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------
  before_save :set_last_updated_at

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :korean_phrase, presence: true
  validate :korean_phrase_unique_per_novel

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  scope :by_korean_phrase, -> { order(:korean_phrase) }

  # ---------------------------------------------------------------------------
  # translation_examples — jsonb array of {"context" => ..., "translation" => ...}.
  # The virtual text accessors below give forms one plain textarea (one
  # example per line, "context: translation") instead of a repeating-fields
  # UI, round-tripped through the real jsonb column.
  # ---------------------------------------------------------------------------
  def translation_examples_text
    translation_examples.to_a.map { |ex|
      ctx = ex["context"].presence
      tr  = ex["translation"]
      ctx ? "#{ctx}: #{tr}" : tr.to_s
    }.join("\n")
  end

  def translation_examples_text=(text)
    self.translation_examples = text.to_s.each_line.map(&:strip).reject(&:blank?).map { |line|
      ctx, sep, tr = line.partition(":")
      sep.present? ? { "context" => ctx.strip, "translation" => tr.strip }
                   : { "context" => nil, "translation" => line }
    }
  end

  # ---------------------------------------------------------------------------
  # Embeddable implementation
  # ---------------------------------------------------------------------------
  def embeddable_text
    [
      korean_phrase,
      literal_translation,
      intended_meaning,
      context,
      translation_examples_text,
      notes
    ].compact.reject(&:blank?).join(" ")
  end

  # ---------------------------------------------------------------------------
  # BibleDocSynced implementation
  # ---------------------------------------------------------------------------
  def bible_doc_category
    :cultural_phrases
  end

  private

  def set_last_updated_at
    self.last_updated_at = Time.current
  end

  # DB-level unique index (novel_id, korean_phrase) catches exact-string
  # collisions cheaply at the database. This additionally catches
  # near-duplicates the raw index can't — differing whitespace, full/half-width
  # characters, Latin-script casing — via the same normalisation preread's
  # matching uses (see Pipeline::BibleUtils.normalize_korean, docs/DECISIONS.md
  # 2026-08-08 "korean_key is the one normalisation point"). A per-novel
  # in-Ruby scan is fine at this app's scale (currently double digits of
  # cultural-phrase entries per novel); revisit if that ever changes.
  def korean_phrase_unique_per_novel
    return if korean_phrase.blank? || novel_id.blank?

    normalized = Pipeline::BibleUtils.normalize_korean(korean_phrase)
    collision = novel.bible_cultural_phrases.where.not(id: id).any? { |r|
      Pipeline::BibleUtils.normalize_korean(r.korean_phrase) == normalized
    }
    errors.add(:korean_phrase, "is already in the bible for this novel") if collision
  end
end
