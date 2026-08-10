# Thin resolution endpoints for one bible_entry_proposal — approve writes
# its fields onto the live bible record, skip records the dismissal.
# Neither the matcher nor the ingester is touched from here; both actions
# delegate straight to the model (docs/PREREAD_STAGING_DESIGN.md).
#
# Two callers: the /preread_review slideshow (fires these per-card via
# fetch, immediate persist, no batch submit) and each bible category
# page's "Pending suggestions" tab (a plain non-Turbo form, "Dismiss" only
# — see BiblePrereadDismissed).
class BibleEntryProposalsController < ApplicationController
  before_action :set_novel
  before_action :set_proposal

  def approve
    @proposal.approve!
    respond_to_resolution
  end

  def skip
    @proposal.skip!
    respond_to_resolution
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_proposal
    @proposal = @novel.bible_entry_proposals.find(params[:id])
  end

  # JSON for the slideshow's own fetch calls (it manages card
  # removal/progress entirely client-side, same as before — see
  # app/javascript/controllers/preread_review_controller.ts); a plain
  # redirect for the category pages' non-JS "Dismiss" form.
  def respond_to_resolution
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_back fallback_location: novel_preread_review_path(@novel) }
    end
  end
end
