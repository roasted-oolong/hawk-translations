# Shared by the four Korean-bearing bible_*_controllers' #create actions.
# BibleLookupController's quick-create popover (Tab-select → "Create as
# Character/…") knows which chapter the selection came from and sends it as
# chapter_id — this fills first_appearance_chapter from that chapter's
# number automatically, the one bible field that's fully derivable without
# asking the user or the LLM suggestion (Pipeline::BibleEntrySuggestion)
# for anything. Every other bible-entry creation path (the full /new form,
# bible_import) simply never sends chapter_id, so this is a no-op there.
module BibleEntryChapterPrefill
  extend ActiveSupport::Concern

  private

  # Never overrides a value entry_params already supplied — a param sent
  # deliberately always wins over this best-effort fill-in.
  def prefill_first_appearance_chapter(entry)
    return if entry.first_appearance_chapter.present?
    return if params[:chapter_id].blank?

    chapter = @novel.chapters.find_by(id: params[:chapter_id])
    entry.first_appearance_chapter = chapter.number if chapter
  end
end
