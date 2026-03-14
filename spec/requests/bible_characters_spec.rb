require "rails_helper"

RSpec.describe "BibleCharacters", type: :request do
  let(:user)      { create(:user) }
  let(:novel)     { create(:novel) }
  let!(:character) { create(:bible_character, novel: novel, name: "Kang Jinha") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible_characters" do
    it "returns 200 and lists characters" do
      get novel_bible_characters_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_characters/:id" do
    it "returns 200 and shows the character" do
      get novel_bible_character_path(novel, character)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_characters/new" do
    it "returns 200" do
      get new_novel_bible_character_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /novels/:novel_id/bible_characters" do
    context "with valid params" do
      it "creates a character and redirects to show" do
        expect {
          post novel_bible_characters_path(novel), params: {
            bible_character: { name: "Lee Sooha", role: "Protagonist" }
          }
        }.to change(BibleCharacter, :count).by(1)

        expect(response).to redirect_to(novel_bible_character_path(novel, BibleCharacter.last))
      end
    end

    context "with missing name" do
      it "does not create a character and re-renders new" do
        expect {
          post novel_bible_characters_path(novel), params: {
            bible_character: { name: nil }
          }
        }.not_to change(BibleCharacter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:novel_id/bible_characters/:id/edit" do
    it "returns 200" do
      get edit_novel_bible_character_path(novel, character)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/bible_characters/:id" do
    it "updates and redirects to show" do
      patch novel_bible_character_path(novel, character), params: {
        bible_character: { role: "Antagonist" }
      }
      expect(response).to redirect_to(novel_bible_character_path(novel, character))
      expect(character.reload.role).to eq("Antagonist")
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_character_path(novel, character), params: {
        bible_character: { name: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /novels/:novel_id/bible_characters/:id" do
    it "destroys the character and redirects to index" do
      expect {
        delete novel_bible_character_path(novel, character)
      }.to change(BibleCharacter, :count).by(-1)

      expect(response).to redirect_to(novel_bible_characters_path(novel))
    end
  end
end
