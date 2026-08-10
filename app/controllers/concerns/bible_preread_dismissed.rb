module BiblePrereadDismissed
  extend ActiveSupport::Concern

  # PREREAD_CATEGORY (each including controller's own plural symbol, e.g.
  # :characters — the legacy plural vocabulary preread_dismissed_keys and
  # Pipeline::BibleEntryMatcher's category param still use) -> BibleEntryProposal's
  # own singular entry_type. Same shape as
  # BibleEntryProposal::ENTRY_TYPE_TO_LEGACY_SECTION (inverted) and
  # Pipeline::BibleEntryProposalIngester::SECTION_TO_ENTRY_TYPE — each of
  # the three lives with the class that actually needs that direction of
  # the mapping, matching how this app already keeps a "5 bible
  # categories" table per class that needs one (Pipeline::BibleEntryDocWriter::
  # FILE_MAP/HEADER_TITLE, Pipeline::BibleEntryMatcher::COMPARABLE_FIELDS)
  # rather than a single shared constant every unrelated class reaches into.
  CATEGORY_TO_ENTRY_TYPE = {
    characters:       "character",
    locations:        "location",
    terminology:      "terminology",
    cultural_phrases: "cultural_phrase",
    story:            "story"
  }.freeze

  included do
    before_action :load_dismissed_preread_entries, only: :index
    before_action :load_pending_preread_entries, only: :index
  end

  private

  # preread_dismissed_keys only ever holds bare "section:korean_key"
  # strings — since BibleEntryProposal#skip! deletes the proposal row it
  # came from, there's no longer a record anywhere to look up a name/
  # Korean-name/etc for. Restoring shows the Korean key alone; see
  # PrereadDismissController#destroy's updated copy for what "restore"
  # means now.
  def load_dismissed_preread_entries
    keys = begin
      JSON.parse(@novel.preread_dismissed_keys || "[]")
    rescue JSON::ParserError
      []
    end
    prefix = "#{self.class::PREREAD_CATEGORY}:"
    @dismissed_preread_entries = keys.select { |k| k.start_with?(prefix) }.map { |k| k.delete_prefix(prefix) }
  end

  # Suggestions awaiting review — same source as /preread_review, surfaced here too so a
  # suggestion can be dismissed outright without going through the whole review slideshow.
  def load_pending_preread_entries
    entry_type = CATEGORY_TO_ENTRY_TYPE.fetch(self.class::PREREAD_CATEGORY)
    @pending_preread_entries = @novel.bible_entry_proposals.where(entry_type: entry_type).order(:korean_key)
  end
end
