require "rails_helper"

RSpec.describe "BibleImport", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "POST /novels/:novel_id/bible_import" do
    context "when approved_entries is an empty array and skipped_entries has keys" do
      it "stores skipped keys as dismissed and redirects to novel" do
        skipped = [ "characters:김민준", "locations:서울" ]

        post novel_bible_import_path(novel),
          params: { approved_entries: "[]", skipped_entries: skipped.to_json }

        expect(response).to redirect_to(novel_path(novel))
        novel.reload
        dismissed = JSON.parse(novel.preread_dismissed_keys)
        expect(dismissed).to match_array(skipped)
      end
    end

    context "when called twice with overlapping skipped keys" do
      it "deduplicates dismissed keys" do
        post novel_bible_import_path(novel),
          params: { approved_entries: "[]", skipped_entries: '["characters:김민준"]' }
        post novel_bible_import_path(novel),
          params: { approved_entries: "[]", skipped_entries: '["characters:김민준", "locations:서울"]' }

        novel.reload
        dismissed = JSON.parse(novel.preread_dismissed_keys)
        expect(dismissed.uniq).to eq(dismissed)
        expect(dismissed).to include("characters:김민준", "locations:서울")
      end
    end

    context "when skipped_entries is absent" do
      it "does not change dismissed keys" do
        post novel_bible_import_path(novel),
          params: { approved_entries: "[]" }

        novel.reload
        expect(novel.preread_dismissed_keys).to eq("[]")
      end
    end

    context "when approving a new story entry" do
      it "saves it with its own category, not the bible-section selector" do
        approved = [ {
          title: "The Lost Heir", content: "Some content.", category: "main_plot",
          bible_category: "story"
        } ]

        post novel_bible_import_path(novel),
          params: { approved_entries: approved.to_json, skipped_entries: "[]" }

        expect(novel.bible_story_entries.count).to eq(1)
        expect(novel.bible_story_entries.first.category).to eq("main_plot")
      end
    end

    context "when approving an update to an existing story entry" do
      it "updates its category along with the rest of the record" do
        entry = novel.bible_story_entries.create!(title: "The Lost Heir", content: "old", category: "subplot")
        approved = [ {
          title: "The Lost Heir", content: "new content", category: "main_plot",
          existing_id: entry.id, bible_category: "story"
        } ]

        post novel_bible_import_path(novel),
          params: { approved_entries: approved.to_json, skipped_entries: "[]" }

        entry.reload
        expect(entry.content).to eq("new content")
        expect(entry.category).to eq("main_plot")
      end
    end

    context "when approving an update to an existing character (non-story sanity check)" do
      it "updates the record" do
        char = novel.bible_characters.create!(name: "Old", korean_name: "구", role: "villain")
        approved = [ {
          name: "New", korean_name: "구", role: "hero",
          existing_id: char.id, bible_category: "characters"
        } ]

        post novel_bible_import_path(novel),
          params: { approved_entries: approved.to_json, skipped_entries: "[]" }

        char.reload
        expect(char.name).to eq("New")
        expect(char.role).to eq("hero")
      end
    end
  end
end
