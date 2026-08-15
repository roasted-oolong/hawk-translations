require "rails_helper"

RSpec.describe "ChapterReview resume position", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }
  let!(:chapter) { create(:chapter, novel: novel, number: 1, status: "translated") }

  before { sign_in(user) }

  describe "PATCH /novels/:novel_id/chapter_review/chapters/:id/position" do
    it "records the scroll fraction on the chapter and marks it the novel's last-reviewed chapter" do
      patch novel_update_chapter_review_position_path(novel, chapter), params: { scroll_position: 0.42 }

      expect(response).to have_http_status(:ok)
      expect(chapter.reload.last_scroll_position).to eq(0.42)
      expect(novel.reload.last_reviewed_chapter_id).to eq(chapter.id)
    end

    it "clamps out-of-range values instead of storing them raw" do
      patch novel_update_chapter_review_position_path(novel, chapter), params: { scroll_position: 4.2 }
      expect(chapter.reload.last_scroll_position).to eq(1.0)

      patch novel_update_chapter_review_position_path(novel, chapter), params: { scroll_position: -1 }
      expect(chapter.reload.last_scroll_position).to eq(0.0)
    end

    it "400s when scroll_position is missing" do
      patch novel_update_chapter_review_position_path(novel, chapter), params: {}

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /novels/:novel_id/chapter_review reopens on the last-reviewed chapter" do
    it "starts the slideshow at the saved chapter, not chapter 1" do
      other = create(:chapter, novel: novel, number: 2, status: "translated")
      novel.update!(last_reviewed_chapter: other)

      get novel_chapter_review_path(novel)

      expect(response.body).to include('data-chapter-review-resume-index-value="1"')
    end

    it "falls back to 0 when the saved chapter is no longer in the review queue" do
      reviewed = create(:chapter, novel: novel, number: 2, status: "reviewed")
      novel.update!(last_reviewed_chapter: reviewed)

      get novel_chapter_review_path(novel)

      expect(response.body).to include('data-chapter-review-resume-index-value="0"')
    end
  end
end
