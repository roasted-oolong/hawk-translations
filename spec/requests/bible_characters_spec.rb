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

    it "prefills name from prefill_name param" do
      get new_novel_bible_character_path(novel), params: { prefill_name: "Park Jihoon" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Park Jihoon")
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

    context "with a chapter_id param (bible-lookup quick-create)" do
      let(:chapter) { create(:chapter, novel: novel, number: 7) }

      it "fills first_appearance_chapter from the chapter's number" do
        post novel_bible_characters_path(novel), params: {
          bible_character: { name: "Lee Sooha" }, chapter_id: chapter.id
        }
        expect(BibleCharacter.last.first_appearance_chapter).to eq(7)
      end

      it "does not override first_appearance_chapter if one was already given" do
        post novel_bible_characters_path(novel), params: {
          bible_character: { name: "Lee Sooha", first_appearance_chapter: 2 }, chapter_id: chapter.id
        }
        expect(BibleCharacter.last.first_appearance_chapter).to eq(2)
      end

      it "leaves first_appearance_chapter blank for an unknown chapter_id" do
        post novel_bible_characters_path(novel), params: {
          bible_character: { name: "Lee Sooha" }, chapter_id: 0
        }
        expect(BibleCharacter.last.first_appearance_chapter).to be_nil
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

    it "returns JSON on successful update when requested" do
      patch novel_bible_character_path(novel, character),
            params: { bible_character: { role: "Antagonist" } },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("display_name" => character.name)
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_character_path(novel, character), params: {
        bible_character: { name: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns JSON errors on invalid params when requested" do
      patch novel_bible_character_path(novel, character),
            params: { bible_character: { name: "" } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("errors")
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

  describe "GET /novels/:novel_id/bible_characters — pending preread suggestions tab" do
    let!(:proposal) do
      chapter = create(:chapter, novel: novel)
      create(:bible_entry_proposal, novel: novel, chapter: chapter, entry_type: "character",
             korean_key: "유아름", fields: { "name" => "Yoo Areum", "korean_name" => "유아름", "role" => "Sidekick" })
    end

    it "lists the pending suggestion with a Dismiss action" do
      get novel_bible_characters_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Yoo Areum")
      expect(response.body).to include("Pending suggestions")
    end

    it "dismissing it via bible_entry_proposals#skip moves it out of the pending list and into dismissed" do
      post skip_novel_bible_entry_proposal_path(novel, proposal)

      get novel_bible_characters_path(novel)
      expect(response.body).to include("No pending preread suggestions")
      expect(response.body).to include("Dismissed preread")
      expect(response.body).to include("유아름") # now shown in the dismissed panel as a bare Korean key
    end
  end
end
