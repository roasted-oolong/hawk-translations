module BiblePrereadDismissed
  extend ActiveSupport::Concern

  included do
    before_action :load_dismissed_preread_entries, only: :index
    before_action :load_pending_preread_entries, only: :index
  end

  private

  def load_dismissed_preread_entries
    @dismissed_preread_entries = BibleMarkdownParser.new(@novel)
                                                    .dismissed_entries_for(self.class::PREREAD_CATEGORY)
  end

  # Suggestions awaiting review — same source as /preread_review, surfaced here too so a
  # suggestion can be dismissed outright without going through the whole review slideshow.
  def load_pending_preread_entries
    @pending_preread_entries = BibleMarkdownParser.new(@novel)
                                                   .pending_entries[self.class::PREREAD_CATEGORY]
  end
end
