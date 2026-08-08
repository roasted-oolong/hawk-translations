require "rails_helper"

RSpec.describe "BibleTerminologies", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }
  let!(:term) { create(:bible_terminology, novel: novel, term: "S-Rank") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible_terminologies" do
    it "returns 200 and lists terms" do
      get novel_bible_terminologies_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_terminologies/:id" do
    it "returns 200 and shows the term" do
      get novel_bible_terminology_path(novel, term)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_terminologies/new" do
    it "returns 200" do
      get new_novel_bible_terminology_path(novel)
      expect(response).to have_http_status(:ok)
    end

    it "prefills term from prefill_name param" do
      get new_novel_bible_terminology_path(novel), params: { prefill_name: "Gate Dungeon" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gate Dungeon")
    end
  end

  describe "POST /novels/:novel_id/bible_terminologies" do
    context "with valid params" do
      it "creates a term and redirects to show" do
        expect {
          post novel_bible_terminologies_path(novel), params: {
            bible_terminology: { term: "Gate", definition: "A rift to a dungeon dimension." }
          }
        }.to change(BibleTerminology, :count).by(1)

        expect(response).to redirect_to(novel_bible_terminology_path(novel, BibleTerminology.last))
      end
    end

    context "with missing term" do
      it "does not create a term and re-renders new" do
        expect {
          post novel_bible_terminologies_path(novel), params: {
            bible_terminology: { term: nil }
          }
        }.not_to change(BibleTerminology, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a chapter_id param (bible-lookup quick-create)" do
      it "fills first_appearance_chapter from the chapter's number" do
        chapter = create(:chapter, novel: novel, number: 7)
        post novel_bible_terminologies_path(novel), params: {
          bible_terminology: { term: "Gate" }, chapter_id: chapter.id
        }
        expect(BibleTerminology.last.first_appearance_chapter).to eq(7)
      end
    end
  end

  describe "GET /novels/:novel_id/bible_terminologies/:id/edit" do
    it "returns 200" do
      get edit_novel_bible_terminology_path(novel, term)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/bible_terminologies/:id" do
    it "updates and redirects to show" do
      patch novel_bible_terminology_path(novel, term), params: {
        bible_terminology: { definition: "Updated definition." }
      }
      expect(response).to redirect_to(novel_bible_terminology_path(novel, term))
      expect(term.reload.definition).to eq("Updated definition.")
    end

    it "returns JSON on successful update when requested" do
      patch novel_bible_terminology_path(novel, term),
            params: { bible_terminology: { definition: "Updated definition." } },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("display_name" => term.term)
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_terminology_path(novel, term), params: {
        bible_terminology: { term: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns JSON errors on invalid params when requested" do
      patch novel_bible_terminology_path(novel, term),
            params: { bible_terminology: { term: "" } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  describe "DELETE /novels/:novel_id/bible_terminologies/:id" do
    it "destroys the term and redirects to index" do
      expect {
        delete novel_bible_terminology_path(novel, term)
      }.to change(BibleTerminology, :count).by(-1)

      expect(response).to redirect_to(novel_bible_terminologies_path(novel))
    end
  end
end
