require "rails_helper"

RSpec.describe "PrereadReview", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/preread_review" do
    it "redirects to the novel page when there are no pending proposals" do
      get novel_preread_review_path(novel)

      expect(response).to redirect_to(novel_path(novel))
      follow_redirect!
      expect(response.body).to include("No pending preread entries")
    end

    # Full-page slideshow render (@proposals.any?) is covered once the view
    # is rebuilt against BibleEntryProposal — see
    # docs/PREREAD_STAGING_DESIGN.md Group B7.
  end
end
