require "rails_helper"

RSpec.describe "ChapterReview tab", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/chapters/review" do
    it "renders the preread-entries-status target for Turbo Stream pushes to replace" do
      get novel_chapter_review_tab_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="preread-entries-status"')
    end
  end
end
