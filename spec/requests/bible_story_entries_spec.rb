require "rails_helper"

RSpec.describe "BibleStoryEntries", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }
  let!(:entry) { create(:bible_story_entry, novel: novel, title: "The Regression", category: "main_plot") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible_story_entries" do
    it "returns 200 and lists entries" do
      get novel_bible_story_entries_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_story_entries/:id" do
    it "returns 200 and shows the entry" do
      get novel_bible_story_entry_path(novel, entry)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_story_entries/new" do
    it "returns 200" do
      get new_novel_bible_story_entry_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /novels/:novel_id/bible_story_entries" do
    context "with valid params" do
      it "creates an entry and redirects to show" do
        expect {
          post novel_bible_story_entries_path(novel), params: {
            bible_story_entry: {
              title:    "The Power System",
              category: "subplot",
              content:  "Hunters gain abilities after awakening."
            }
          }
        }.to change(BibleStoryEntry, :count).by(1)

        expect(response).to redirect_to(novel_bible_story_entry_path(novel, BibleStoryEntry.last))
      end
    end

    context "with missing title" do
      it "does not create and re-renders new" do
        expect {
          post novel_bible_story_entries_path(novel), params: {
            bible_story_entry: { title: nil, category: "main_plot" }
          }
        }.not_to change(BibleStoryEntry, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with missing category" do
      it "does not create and re-renders new" do
        expect {
          post novel_bible_story_entries_path(novel), params: {
            bible_story_entry: { title: "Something", category: nil }
          }
        }.not_to change(BibleStoryEntry, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:novel_id/bible_story_entries/:id/edit" do
    it "returns 200" do
      get edit_novel_bible_story_entry_path(novel, entry)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/bible_story_entries/:id" do
    it "updates and redirects to show" do
      patch novel_bible_story_entry_path(novel, entry), params: {
        bible_story_entry: { content: "Updated content." }
      }
      expect(response).to redirect_to(novel_bible_story_entry_path(novel, entry))
      expect(entry.reload.content).to eq("Updated content.")
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_story_entry_path(novel, entry), params: {
        bible_story_entry: { title: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /novels/:novel_id/bible_story_entries/:id" do
    it "destroys the entry and redirects to index" do
      expect {
        delete novel_bible_story_entry_path(novel, entry)
      }.to change(BibleStoryEntry, :count).by(-1)

      expect(response).to redirect_to(novel_bible_story_entries_path(novel))
    end
  end
end
