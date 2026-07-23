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

      it "removes the key and redirects to preread review on dismissed tab" do
        delete novel_preread_dismiss_path(novel), params: { key: "characters:김민준" }

        expect(response).to redirect_to(novel_preread_review_path(novel, tab: "dismissed"))
        novel.reload
        dismissed = JSON.parse(novel.preread_dismissed_keys)
        expect(dismissed).to eq(["locations:서울"])
      end
    end

    context "when the key is not in dismissed keys" do
      before { novel.update_column(:preread_dismissed_keys, '["locations:서울"]') }

      it "leaves dismissed keys unchanged and redirects" do
        delete novel_preread_dismiss_path(novel), params: { key: "characters:김민준" }

        expect(response).to redirect_to(novel_preread_review_path(novel, tab: "dismissed"))
        novel.reload
        expect(JSON.parse(novel.preread_dismissed_keys)).to eq(["locations:서울"])
      end
    end
  end
end
