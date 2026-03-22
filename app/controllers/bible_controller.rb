# frozen_string_literal: true

# =============================================================================
# BibleController
#
# Landing page for a novel's Translation Bible. Provides the search UI and
# a summary of all five category entry counts, linking out to each category
# index. The search endpoint itself is handled by BibleSearchController.
#
# Routes:
#   GET /novels/:novel_id/bible  →  bible#show
# =============================================================================
class BibleController < ApplicationController
  before_action :set_novel

  def show
    @bible_counts = {
      characters:       @novel.bible_characters.count,
      locations:        @novel.bible_locations.count,
      terminology:      @novel.bible_terminologies.count,
      cultural_phrases: @novel.bible_cultural_phrases.count,
      story_entries:    @novel.bible_story_entries.count
    }
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
