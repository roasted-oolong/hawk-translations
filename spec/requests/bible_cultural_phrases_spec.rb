require "rails_helper"

RSpec.describe "BibleCulturalPhrases", type: :request do
  let(:user)   { create(:user) }
  let(:novel)  { create(:novel) }
  let!(:phrase) { create(:bible_cultural_phrase, novel: novel, korean_phrase: "후배") }

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

    it "prefills korean_phrase from prefill_name param" do
      get new_novel_bible_cultural_phrase_path(novel), params: { prefill_name: "눈치 없다" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("눈치 없다")
    end
  end

  describe "POST /novels/:novel_id/bible_cultural_phrases" do
    context "with valid params" do
      it "creates a phrase and redirects to show" do
        expect {
          post novel_bible_cultural_phrases_path(novel), params: {
            bible_cultural_phrase: {
              korean_phrase: "선배",
              translation_examples_text: "formal: senior colleague\ncasual: sunbae"
            }
          }
        }.to change(BibleCulturalPhrase, :count).by(1)

        # Create redirects to edit, not show — see the controller's own
        # notice ("Fill in the details below"), same pattern as the other
        # four bible entry types. Pre-existing behavior, unrelated to this
        # spec's rewrite for the schema change.
        expect(response).to redirect_to(edit_novel_bible_cultural_phrase_path(novel, BibleCulturalPhrase.last))
        expect(BibleCulturalPhrase.last.translation_examples).to eq([
          { "context" => "formal", "translation" => "senior colleague" },
          { "context" => "casual", "translation" => "sunbae" }
        ])
      end
    end

    context "with missing korean_phrase" do
      it "does not create and re-renders new" do
        expect {
          post novel_bible_cultural_phrases_path(novel), params: {
            bible_cultural_phrase: { korean_phrase: nil }
          }
        }.not_to change(BibleCulturalPhrase, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a duplicate korean_phrase in the same novel" do
      it "does not create and re-renders new" do
        expect {
          post novel_bible_cultural_phrases_path(novel), params: {
            bible_cultural_phrase: { korean_phrase: phrase.korean_phrase }
          }
        }.not_to change(BibleCulturalPhrase, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a chapter_id param (bible-lookup quick-create)" do
      it "fills first_appearance_chapter from the chapter's number" do
        chapter = create(:chapter, novel: novel, number: 7)
        post novel_bible_cultural_phrases_path(novel), params: {
          bible_cultural_phrase: { korean_phrase: "선배" }, chapter_id: chapter.id
        }
        expect(BibleCulturalPhrase.last.first_appearance_chapter).to eq(7)
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
        bible_cultural_phrase: { notes: "Junior colleague, casual register" }
      }
      expect(response).to redirect_to(novel_bible_cultural_phrase_path(novel, phrase))
      expect(phrase.reload.notes).to eq("Junior colleague, casual register")
    end

    it "returns JSON on successful update when requested" do
      patch novel_bible_cultural_phrase_path(novel, phrase),
            params: { bible_cultural_phrase: { notes: "Junior colleague" } },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("display_name" => phrase.korean_phrase)
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_cultural_phrase_path(novel, phrase), params: {
        bible_cultural_phrase: { korean_phrase: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns JSON errors on invalid params when requested" do
      patch novel_bible_cultural_phrase_path(novel, phrase),
            params: { bible_cultural_phrase: { korean_phrase: "" } },
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
