require "rails_helper"

RSpec.describe "BibleImport", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "POST /novels/:novel_id/bible_import" do
    context "when approved_entries is an empty array and skipped_entries has keys" do
      it "stores skipped keys as dismissed and redirects to novel" do
        skipped = ["characters:김민준", "locations:서울"]

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
  end
end
