require "rails_helper"

RSpec.describe "BibleCulturalPhrases", type: :request do
  let(:user)   { create(:user) }
  let(:novel)  { create(:novel) }
  let!(:phrase) { create(:bible_cultural_phrase, novel: novel, phrase: "Hoobae") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible_cultural_phrases" do
    it "returns 200 and lists phrases" do
      get novel_bible_cultural_phrases_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_cultural_phrases/:id" do
    it "returns 200 and shows the phrase" do
      get novel_bible_cultural_phrase_path(novel, phrase)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_cultural_phrases/new" do
    it "returns 200" do
      get new_novel_bible_cultural_phrase_path(novel)
      expect(response).to have_http_status(:ok)
    end

    it "prefills phrase from prefill_name param" do
      get new_novel_bible_cultural_phrase_path(novel), params: { prefill_name: "sunbae-nim" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sunbae-nim")
    end
  end

  describe "POST /novels/:novel_id/bible_cultural_phrases" do
    context "with valid params" do
      it "creates a phrase and redirects to show" do
        expect {
          post novel_bible_cultural_phrases_path(novel), params: {
            bible_cultural_phrase: {
              phrase: "Sunbae",
              established_translation: "Senior"
            }
          }
        }.to change(BibleCulturalPhrase, :count).by(1)

        expect(response).to redirect_to(novel_bible_cultural_phrase_path(novel, BibleCulturalPhrase.last))
      end
    end

    context "with missing phrase" do
      it "does not create and re-renders new" do
        expect {
          post novel_bible_cultural_phrases_path(novel), params: {
            bible_cultural_phrase: { phrase: nil }
          }
        }.not_to change(BibleCulturalPhrase, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:novel_id/bible_cultural_phrases/:id/edit" do
    it "returns 200" do
      get edit_novel_bible_cultural_phrase_path(novel, phrase)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/bible_cultural_phrases/:id" do
    it "updates and redirects to show" do
      patch novel_bible_cultural_phrase_path(novel, phrase), params: {
        bible_cultural_phrase: { established_translation: "Junior colleague" }
      }
      expect(response).to redirect_to(novel_bible_cultural_phrase_path(novel, phrase))
      expect(phrase.reload.established_translation).to eq("Junior colleague")
    end

    it "returns JSON on successful update when requested" do
      patch novel_bible_cultural_phrase_path(novel, phrase),
            params: { bible_cultural_phrase: { established_translation: "Junior colleague" } },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("display_name" => phrase.phrase)
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_cultural_phrase_path(novel, phrase), params: {
        bible_cultural_phrase: { phrase: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns JSON errors on invalid params when requested" do
      patch novel_bible_cultural_phrase_path(novel, phrase),
            params: { bible_cultural_phrase: { phrase: "" } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
    end
  end

  describe "DELETE /novels/:novel_id/bible_cultural_phrases/:id" do
    it "destroys the phrase and redirects to index" do
      expect {
        delete novel_bible_cultural_phrase_path(novel, phrase)
      }.to change(BibleCulturalPhrase, :count).by(-1)

      expect(response).to redirect_to(novel_bible_cultural_phrases_path(novel))
    end
  end
end
