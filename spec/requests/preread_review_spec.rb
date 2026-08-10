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

    it "renders the slideshow with a card per pending proposal" do
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character",
             korean_key: "성아", fields: { "name" => "Sung-ah", "korean_name" => "성아", "role" => "Lead" })
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "location",
             korean_key: "hs", fields: { "name" => "HS Entertainment", "significance" => "Main label" })

      get novel_preread_review_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sung-ah")
      expect(response.body).to include("HS Entertainment")
      expect(response.body.scan('data-testid="preread-entry-card"').size).to eq(2)
    end

    it "tags an entry with no existing_record_id as new, and one with existing_record_id as updating" do
      chapter = create(:chapter, novel: novel)
      character = create(:bible_character, novel: novel, name: "Sung-ah")
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character",
             korean_key: "성아", existing_record_id: character.id, fields: { "name" => "Sung-ah" })
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "location",
             korean_key: "hs", existing_record_id: nil, fields: { "name" => "HS Entertainment" })

      get novel_preread_review_path(novel)

      expect(response.body).to include("Updating existing entry")
      expect(response.body).to include("New entry")
    end

    it "renders the approve/skip/update URL templates for the slideshow's own fetch calls" do
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "성아")

      get novel_preread_review_path(novel)

      expect(response.body).to include("bible_entry_proposals/:id/approve")
      expect(response.body).to include("bible_entry_proposals/:id/skip")
    end
  end
end
