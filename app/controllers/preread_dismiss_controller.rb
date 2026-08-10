class PrereadDismissController < ApplicationController
  before_action :set_novel

  # Removes a key from preread_dismissed_keys — "eligible to be
  # re-suggested on the next preread pass," not an instant return to the
  # pending queue: skip! (BibleEntryProposal) already deleted the proposal
  # row itself, so there's nothing left to un-delete, only the dismissal
  # to lift. #create (dismiss-without-a-proposal-id) is gone — every
  # dismissal now goes through BibleEntryProposalsController#skip on a
  # real proposal, from either the /preread_review slideshow or the bible
  # category pages' "Pending suggestions" tab.
  def destroy
    key      = params.require(:key)
    existing = JSON.parse(@novel.preread_dismissed_keys || "[]") rescue []
    @novel.update_column(:preread_dismissed_keys, existing.reject { |k| k == key }.to_json)
    redirect_back fallback_location: novel_path(@novel), notice: "Removed from dismissed — eligible to be re-suggested on the next preread pass."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
