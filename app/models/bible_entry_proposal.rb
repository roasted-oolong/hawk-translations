# frozen_string_literal: true

# A staged preread suggestion — new or changed bible entry content parsed
# from a preread LLM run, sitting between "the LLM proposed it" and "a human
# approved it." Never read by the translation prompt directly; only the 5
# live bible tables (bible_characters, bible_locations, bible_terminologies,
# bible_cultural_phrases, bible_story_entries) are, via BibleDocSynced's
# DB -> bible/*.md sync.
#
# Resolved rows are deleted, not archived — approve! writes fields onto the
# live record and destroys the proposal; skip! records the korean_key onto
# Novel#preread_dismissed_keys (so a later preread pass over overlapping
# content doesn't just re-propose the same thing) and destroys the proposal.
# See docs/PREREAD_STAGING_DESIGN.md for the full design.
class BibleEntryProposal < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  belongs_to :novel
  belongs_to :chapter

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enum :entry_type, {
    character:       "character",
    location:        "location",
    terminology:     "terminology",
    cultural_phrase: "cultural_phrase",
    story:           "story"
  }

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  validates :korean_key, presence: true
  validates :entry_type, presence: true

  # Which of Novel's bible associations a given entry_type resolves to.
  ENTRY_TYPE_TO_ASSOCIATION = {
    character:       :bible_characters,
    location:        :bible_locations,
    terminology:     :bible_terminologies,
    cultural_phrase: :bible_cultural_phrases,
    story:           :bible_story_entries
  }.freeze

  # entry_type (this table's singular vocabulary) -> the plural section key
  # Pipeline::BibleEntryMatcher's dismissed-key format still uses
  # ("characters:...", not "character:...") — that format predates this
  # table, and stays: the matcher's own #dismissed_keys check is unrelated
  # to (and outlived) the now-deleted BibleMarkdownParser, so this mapping
  # isn't a transitional shim due to be retired, it's the permanent bridge
  # between the two vocabularies. #skip! must write in the format the
  # matcher's dismissed check actually looks for, or a skipped suggestion
  # silently comes right back on the next pass.
  ENTRY_TYPE_TO_LEGACY_SECTION = {
    character:       "characters",
    location:        "locations",
    terminology:     "terminology",
    cultural_phrase: "cultural_phrases",
    story:           "story"
  }.freeze

  # entry_type -> the field keys valid for it, derived from
  # Pipeline::BibleEntryMatcher::COMPARABLE_FIELDS via
  # ENTRY_TYPE_TO_LEGACY_SECTION rather than a fresh literal (same 5
  # categories, one more copy would just be one more place to drift).
  # BibleEntryProposalsController#update's allowlist for inline edits: a
  # field a preread pass never populated (compacted out at parse time)
  # must still be settable by hand, so "keys already in fields" isn't a
  # safe allowlist — "keys valid for this entry_type" is.
  ALLOWED_FIELD_KEYS = ENTRY_TYPE_TO_LEGACY_SECTION.transform_values { |section|
    Pipeline::BibleEntryMatcher::COMPARABLE_FIELDS.fetch(section.to_sym).map(&:to_s)
  }.freeze

  # ---------------------------------------------------------------------------
  # Resolution
  # ---------------------------------------------------------------------------

  # Writes this proposal's fields onto the live bible table (creating or
  # updating as appropriate), then deletes the proposal. Falls back to
  # creating a fresh record if existing_record_id pointed at a row a human
  # deleted directly while this proposal sat pending, rather than raising.
  def approve!
    transaction do
      record = resolve_target_record
      record.assign_attributes(fields)
      record.save!
      destroy!
    end
  end

  # Deletes the proposal and remembers its korean_key so preread doesn't
  # propose the same content again next pass.
  def skip!
    transaction do
      section = ENTRY_TYPE_TO_LEGACY_SECTION.fetch(entry_type.to_sym)
      novel.append_preread_dismissed_key!("#{section}:#{korean_key}")
      destroy!
    end
  end

  private

  def association_name
    ENTRY_TYPE_TO_ASSOCIATION.fetch(entry_type.to_sym)
  end

  def resolve_target_record
    return novel.public_send(association_name).build unless existing_record_id

    novel.public_send(association_name).find(existing_record_id)
  rescue ActiveRecord::RecordNotFound
    novel.public_send(association_name).build
  end
end
