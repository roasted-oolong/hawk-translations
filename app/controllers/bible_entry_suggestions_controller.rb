# =============================================================================
# BibleEntrySuggestionsController
#
# API-first, JSON only. Fired from BibleLookupController's quick-create
# form (bible_lookup_controller.ts) the moment a translator chooses
# "Create as Character/Location/…" after Tab-selecting English text — looks
# up the Korean equivalent and a handful of descriptive fields for that one
# new entry from the chapter's Korean source. See
# Pipeline::BibleEntrySuggestion for why this is scoped to a single entry
# rather than a bible_build-style batch pass.
#
# Always 200 with a (possibly empty) `fields` hash: no Korean source on
# disk, an unrecognized entry type, or the LLM call itself failing all mean
# "nothing to suggest," not a request error — the quick-create form falls
# back to its pre-this-feature blank fields, never an error toward the
# user. A missing novel/chapter is a genuine request error and still 404s.
#
# Routes:
#   POST /novels/:novel_id/bible_entry_suggestion
#
# Params:
#   type       String — one of Pipeline::BibleEntrySuggestion::FIELD_SPECS' keys
#   english    String — the selected English text
#   context    String — surrounding English context (optional)
#   chapter_id Integer — the chapter the selection was made in
#
# Response shape:
#   200 { "fields": { ... } }
#   404                        — novel or chapter not found
# =============================================================================
class BibleEntrySuggestionsController < ApplicationController
  before_action :set_novel
  before_action :set_chapter

  def create
    korean_source_text = KoreanSourceDiskWriter.new(@novel).read(@chapter)

    result = Pipeline::BibleEntrySuggestion.call(
      entry_type:         params[:type].to_s,
      english_text:       params[:english].to_s,
      context_text:       params[:context].to_s,
      korean_source_text: korean_source_text
    )

    render json: { fields: result.fields }
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Novel not found" }, status: :not_found
  end

  def set_chapter
    @chapter = @novel.chapters.find(params[:chapter_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Chapter not found" }, status: :not_found
  end
end
