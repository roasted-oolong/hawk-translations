require "rails_helper"

RSpec.describe "ChapterReview tab", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/chapters/review" do
    it "renders without a poll wrapper when no preread job is active" do
      get novel_chapter_review_tab_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-controller="poll"')
      expect(response.body).to include('id="preread-entries-status"')
    end

    it "wraps the preread entries card in a poll controller while a preread job is queued or running" do
      create(:translation_job, novel: novel, user: user, status: "running")

      get novel_chapter_review_tab_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="poll"')
      expect(response.body).to include(novel_chapter_review_tab_path(novel))
    end

    it "omits the poll wrapper once the preread job is terminal" do
      create(:translation_job, novel: novel, user: user, status: "completed")

      get novel_chapter_review_tab_path(novel)

      expect(response.body).not_to include('data-controller="poll"')
    end
  end
end
