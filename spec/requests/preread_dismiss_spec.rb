require "rails_helper"

RSpec.describe "PrereadDismiss", type: :request do
  let(:user)  { create(:user) }
  let(:novel) { create(:novel) }

  before { sign_in(user) }

  describe "DELETE /novels/:novel_id/preread_dismiss" do
    context "when the key exists in dismissed keys" do
      before do
        novel.update_column(:preread_dismissed_keys, '["characters:김민준","locations:서울"]')
      end

      it "removes the key and redirects back to the bible category page" do
        delete novel_preread_dismiss_path(novel), params: { key: "characters:김민준" }

        # No referer set, so redirect_back falls back to the novel page — restoring
        # is meant to return you to wherever you clicked Restore from (the entry's
        # bible category page, "Dismissed preread" tab), not into a review slideshow.
        expect(response).to redirect_to(novel_path(novel))
        novel.reload
        dismissed = JSON.parse(novel.preread_dismissed_keys)
        expect(dismissed).to eq(["locations:서울"])
      end
    end

    context "when the key is not in dismissed keys" do
      before { novel.update_column(:preread_dismissed_keys, '["locations:서울"]') }

      it "leaves dismissed keys unchanged and redirects" do
        delete novel_preread_dismiss_path(novel), params: { key: "characters:김민준" }

        expect(response).to redirect_to(novel_path(novel))
        novel.reload
        expect(JSON.parse(novel.preread_dismissed_keys)).to eq(["locations:서울"])
      end
    end
  end
end
