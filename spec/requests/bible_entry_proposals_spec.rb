require "rails_helper"

RSpec.describe "BibleEntryProposals", type: :request do
  let(:user)    { create(:user) }
  let(:novel)   { create(:novel) }
  let(:chapter) { create(:chapter, novel: novel) }

  before { sign_in(user) }

  describe "POST /novels/:novel_id/bible_entry_proposals/:id/approve" do
    let!(:proposal) do
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character",
             korean_key: "성아", fields: { "name" => "Sung-ah", "korean_name" => "성아" })
    end

    it "writes the proposal's fields onto a new live record and deletes the proposal" do
      expect {
        post approve_novel_bible_entry_proposal_path(novel, proposal)
      }.to change(BibleCharacter, :count).by(1).and change(BibleEntryProposal, :count).by(-1)

      expect(BibleCharacter.last.name).to eq("Sung-ah")
    end

    it "redirects back for an HTML request" do
      post approve_novel_bible_entry_proposal_path(novel, proposal)
      expect(response).to redirect_to(novel_preread_review_path(novel))
    end

    it "returns no content for a JSON request" do
      post approve_novel_bible_entry_proposal_path(novel, proposal), as: :json
      expect(response).to have_http_status(:no_content)
    end

    it "404s for a proposal belonging to a different novel" do
      other_proposal = create(:bible_entry_proposal)
      post approve_novel_bible_entry_proposal_path(novel, other_proposal)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /novels/:novel_id/bible_entry_proposals/:id/skip" do
    let!(:proposal) do
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character", korean_key: "성아")
    end

    it "deletes the proposal and records the dismissed key" do
      expect {
        post skip_novel_bible_entry_proposal_path(novel, proposal)
      }.to change(BibleEntryProposal, :count).by(-1)

      expect(JSON.parse(novel.reload.preread_dismissed_keys)).to include("characters:성아")
    end

    it "does not create any live bible record" do
      expect {
        post skip_novel_bible_entry_proposal_path(novel, proposal)
      }.not_to change(BibleCharacter, :count)
    end
  end
end
