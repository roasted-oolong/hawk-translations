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

    it "counts bible_entry_proposals for the pending badge, not the bible files" do
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "a")

      get novel_chapter_review_tab_path(novel)

      expect(response.body).to include("1 pending")
    end
  end
end
