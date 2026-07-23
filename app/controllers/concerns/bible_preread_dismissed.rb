module BiblePrereadDismissed
  extend ActiveSupport::Concern

  included do
    before_action :load_dismissed_preread_entries, only: :index
  end

  private

  def load_dismissed_preread_entries
    @dismissed_preread_entries = BibleMarkdownParser.new(@novel)
                                                    .dismissed_entries_for(self.class::PREREAD_CATEGORY)
  end
end
